// TimerViewModel.swift
// ─────────────────────────────────────────────────────────────────────────────
// Watch App target ONLY.
// WidgetCenter.reloadTimelines 호출을 위해 WidgetKit을 import합니다.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import Combine

@MainActor
final class TimerViewModel: ObservableObject {

    static let shared = TimerViewModel()

    // ── 내부 상태 ─────────────────────────────────────────────────────────────
    /// bookID → (sessionStartDate?, accumulatedElapsed)
    private struct Entry {
        var sessionStartDate: Date?
        var accumulated: TimeInterval
        var book: TimerStateManager.BookData
    }
    private var entries: [String: Entry] = [:]
    
    // 디스플레이 타이머와 저장 타이머 분리
    private var displayTimer: AnyCancellable?
    private var saveTimer: AnyCancellable?

    // ── Published (UI 갱신용 tick) ────────────────────────────────────────────
    @Published private(set) var tick: Date = Date()

    private init() {
        startDisplayTimer()
        restoreFromDisk()
    }

    // MARK: - Public Interface

    func startOrResumeTimer(for book: TimerStateManager.BookData, notifyPhone: Bool = true) {
        var entry = entries[book.id] ?? Entry(sessionStartDate: nil, accumulated: 0, book: book)
        guard entry.sessionStartDate == nil else { return }   // 이미 실행 중
        entry.sessionStartDate = Date()
        entry.book = book
        entries[book.id] = entry

        persistEntry(entry, bookID: book.id)
        syncWidget(activeBookID: book.id)
        if notifyPhone { sendCommand(.start, bookID: book.id) }
    }

    func pauseTimer(for bookID: String, notifyPhone: Bool = true) {
        guard var entry = entries[bookID], let start = entry.sessionStartDate else { return }
        entry.accumulated += Date().timeIntervalSince(start)
        entry.sessionStartDate = nil
        entries[bookID] = entry

        persistEntry(entry, bookID: bookID)
        syncWidget(activeBookID: nil)   // 일시정지 → 위젯에 pause 상태 반영
        if notifyPhone { sendCommand(.pause, bookID: bookID) }
    }

    func stopTimer(for bookID: String, notifyPhone: Bool = false) {
        // 1. 메모리에서 활성 타이머 제거
        entries.removeValue(forKey: bookID)
        
        // 2. [수정 포인트] 이전 단계의 TimerStateManager 메서드명에 맞춰 상태 완전 삭제 호출
        TimerStateManager.shared.removeState(forBookID: bookID)
        
        // 3. 위젯 동기화 (entries가 비었으므로 자동으로 .empty 상태가 되어 위젯이 투명하게 숨겨짐)
        syncWidget(activeBookID: firstRunningBookID())
        if notifyPhone { sendCommand(.stop, bookID: bookID) }
    }

    func prepareForCompletion(bookID: String) {
        if isRunning(for: bookID) { pauseTimer(for: bookID, notifyPhone: false) }
        sendCommand(.stop, bookID: bookID)
    }

    func cancelRemoteSession(bookID: String) {
        stopTimer(for: bookID)
        sendCommand(.cancel, bookID: bookID)
    }

    func applyRemoteTimerState(
        bookID: String,
        action: String?,
        isRunning: Bool,
        elapsedTime: TimeInterval
    ) {
        guard let book = TimerStateManager.shared.loadBooks().first(where: { $0.id == bookID }) else {
            return
        }

        if action == "stop" {
            stopTimer(for: bookID)
            return
        }

        var entry = entries[bookID] ?? Entry(sessionStartDate: nil, accumulated: 0, book: book)
        entry.book = book
        entry.accumulated = max(0, elapsedTime)
        entry.sessionStartDate = isRunning ? Date() : nil
        entries[bookID] = entry
        persistEntry(entry, bookID: bookID)
        syncWidget(activeBookID: isRunning ? bookID : nil)
    }

    func applyRemoteTimerState(_ state: SharedTimerState) {
        TimerStateManager.shared.saveState(state, reloadWidget: false)
        guard let bookID = state.bookID,
              let book = TimerStateManager.shared.loadBooks().first(where: { $0.id == bookID }) else { return }

        if state.hasActiveSession {
            entries[bookID] = Entry(
                sessionStartDate: state.isRunning ? state.sessionStartTime : nil,
                accumulated: max(0, state.pausedTime),
                book: book
            )
            syncWidget(activeBookID: state.isRunning ? bookID : nil)
        } else {
            stopTimer(for: bookID)
        }
    }

    func refreshFromDisk() {
        restoreFromDisk()
    }

    func processPendingWidgetAction() {
        guard let defaults = UserDefaults(suiteName: AppGroupKey.suiteName),
              let rawAction = defaults.string(forKey: AppGroupKey.widgetAction),
              let action = TimerSyncAction(rawValue: rawAction),
              let bookID = defaults.string(forKey: AppGroupKey.widgetActionBookID),
              let book = TimerStateManager.shared.loadBooks().first(where: { $0.id == bookID }) else { return }

        defaults.removeObject(forKey: AppGroupKey.widgetAction)
        defaults.removeObject(forKey: AppGroupKey.widgetActionBookID)

        switch action {
        case .start: startOrResumeTimer(for: book)
        case .pause: pauseTimer(for: bookID)
        case .stop: prepareForCompletion(bookID: bookID)
        case .cancel: cancelRemoteSession(bookID: bookID)
        case .requestState: sendCommand(.requestState, bookID: bookID)
        }
    }

    func isRunning(for bookID: String) -> Bool {
        entries[bookID]?.sessionStartDate != nil
    }

    func canStartSession(for bookID: String) -> Bool {
        entries.isEmpty || entries[bookID] != nil
    }

    func getElapsedTime(for bookID: String) -> TimeInterval {
        guard let entry = entries[bookID] else { return 0 }
        if let start = entry.sessionStartDate {
            return entry.accumulated + Date().timeIntervalSince(start)
        }
        return entry.accumulated
    }

    // MARK: - Display & Save Timer

    private func startDisplayTimer() {
        // 1️⃣ UI 갱신용 타이머: 1초마다 발동하여 화면의 초시계가 부드럽게 흐르도록 갱신
        displayTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self else { return }
                self.tick = now
            }
            
        // 2️⃣ 디스크 백업용 타이머: 3초마다 발동
        saveTimer = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.persistAllEntries()
            }
    }

    // MARK: - Disk Persistence

    private func persistEntry(_ entry: Entry, bookID: String) {
        let state = TimerStateManager.TimerState(
            isRunning:        entry.sessionStartDate != nil,
            bookTitle:        entry.book.title,
            currentPage:      entry.book.currentPage,
            totalPages:       entry.book.totalPages,
            elapsedTime:      entry.accumulated,
            sessionStartTime: entry.sessionStartDate,
            pausedTime:       entry.accumulated,
            isTimerMode:      false,
            targetMinutes:    0,
            targetSeconds:    nil,
            timerEndDate:     nil,
            bookID:           bookID,
            format:           entry.book.format,
            startPage:        entry.book.currentPage,
            sessionOriginalStartTime: entry.sessionStartDate
        )
        // [수정 포인트] TimerStateManager의 async 함수 구조에 맞춰 Task로 감쌈
        // ViewModel에서 이미 위젯을 갱신하므로 Manager 쪽의 reloadWidget은 false 처리
        Task {
            await TimerStateManager.shared.saveStateAsync(state, reloadWidget: false)
        }
    }

    private func persistAllEntries() {
        for (id, entry) in entries { persistEntry(entry, bookID: id) }
    }

    private func restoreFromDisk() {
        let allStates = TimerStateManager.shared.loadAllStatesMap()
        let allBooks  = TimerStateManager.shared.loadBooks()
        let bookMap   = Dictionary(uniqueKeysWithValues: allBooks.map { ($0.id, $0) })

        for (bookID, state) in allStates {
            guard let book = bookMap[bookID] else { continue }
            entries[bookID] = Entry(
                sessionStartDate: state.isRunning ? state.sessionStartTime : nil,
                accumulated:      state.pausedTime,
                book:             book
            )
        }
        // 복원 직후 위젯 동기화
        syncWidget(activeBookID: firstRunningBookID())
    }

    // MARK: - Widget Sync

    private func firstRunningBookID() -> String? {
        entries.first(where: { $0.value.sessionStartDate != nil })?.key
    }

    private func sendCommand(_ action: TimerSyncAction, bookID: String) {
        let command = TimerSyncCommand(action: action, bookID: bookID)
        guard let data = try? JSONEncoder().encode(command) else { return }
        WatchSessionManager.shared.sendMessage(["type": "timerCommand", "command": data])
    }

    /// 가장 최근에 활성화된 타이머를 위젯에 동기화
    func syncWidget(activeBookID: String?) {
        var widgetState: WidgetTimerState

        if let bookID = activeBookID, let entry = entries[bookID] {
            // 1. 실행 중인 타이머가 있을 때
            widgetState = WidgetTimerState(
                bookID:            bookID,
                bookTitle:         entry.book.title,
                bookAuthor:        entry.book.author,
                currentPage:       entry.book.currentPage,
                totalPages:        entry.book.totalPages,
                sessionStartDate:  entry.sessionStartDate,
                accumulatedElapsed: entry.accumulated
            )
        } else if let pausedID = entries.keys.first, let entry = entries[pausedID] {
            // 2. 일시정지 상태일 때 (타이머가 멈춰있음을 보여줌)
            widgetState = WidgetTimerState(
                bookID:            pausedID,
                bookTitle:         entry.book.title,
                bookAuthor:        entry.book.author,
                currentPage:       entry.book.currentPage,
                totalPages:        entry.book.totalPages,
                sessionStartDate:  nil,
                accumulatedElapsed: entry.accumulated
            )
        } else {
            // 3. 실행 중이거나 정지된 타이머가 아예 없을 때 (stopTimer 호출 시)
            // -> 이 상태가 되면 위젯이 투명하게 숨겨집니다.
            widgetState = .empty
        }

        widgetState.save()
    }
}
