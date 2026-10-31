//
//  WatchConnectivity.swift
//  FocusReader
//

import Foundation
import WatchConnectivity
import SwiftData
import WidgetKit

final class WatchSyncManager: NSObject, WCSessionDelegate {
    
    static let shared = WatchSyncManager()
    private let appGroupID = "group.com.Jaemin.FocusReader"
    
    // ✅ modelContext가 주입될 때까지 보류된 작업을 저장하는 배열
    var modelContext: ModelContext? {
        didSet {
            if modelContext != nil {
                flushPendingContextTasks()
            }
        }
    }
    private var pendingContextTasks: [() -> Void] = []
    
    private var isSessionActivated = false
    private var handledCommandIDs: Set<UUID> = []
    
    private override init() { super.init() }
    
    func start() {
        activate()
        // 앱 실행 시 AppGroup에 쌓인 세션들을 처리
        processPendingSessions()
    }
    
    private func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
    
    // ✅ modelContext가 아직 없으면 클로저로 묶어서 대기열에 저장, 있으면 즉시 실행
    private func performWithContext(task: @escaping (ModelContext) -> Void) {
        if let context = modelContext {
            task(context)
        } else {
            print("⏳ 아이폰: modelContext가 아직 주입되지 않아 작업을 대기열에 추가합니다.")
            pendingContextTasks.append { [weak self] in
                guard let self = self, let context = self.modelContext else { return }
                task(context)
            }
        }
    }
    
    // 대기열에 있던 작업들을 한 번에 실행
    private func flushPendingContextTasks() {
        guard !pendingContextTasks.isEmpty else { return }
        print("✅ 아이폰: modelContext 주입 완료. 대기 중인 \(pendingContextTasks.count)개의 작업을 실행합니다.")
        pendingContextTasks.forEach { $0() }
        pendingContextTasks.removeAll()
    }
    
    func sendBooksToWatch(_ books: [TimerStateManager.BookData], isFullSnapshot: Bool = false) {
        saveBooksToAppGroup(books, isFullSnapshot: isFullSnapshot)
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        
        guard isSessionActivated else {
            return
        }
        guard let data = try? JSONEncoder().encode(books) else { return }
        let payload: [String: Any] = [
            "type": "booksSync",
            "books": data,
            "isFullSnapshot": isFullSnapshot,
            "sentAt": Date().timeIntervalSince1970
        ]
        
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo(payload)
            }
        } else {
            WCSession.default.transferUserInfo(payload)
        }
    }
    
    func sendDueReminderGroupToWatch(_ payload: WatchDueReminderScheduler.DueGroupPayload) {
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(payload) else { return }
        
        let msg: [String: Any] = ["type": "dueReminderGroup", "payload": data]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil) { _ in WCSession.default.transferUserInfo(msg) }
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }
    
    func cancelDueReminderGroupOnWatch(dateKey: String) {
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let msg: [String: Any] = ["type": "cancelDueReminderGroup", "dateKey": dateKey]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil) { _ in WCSession.default.transferUserInfo(msg) }
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }
    
    // 💡 실시간 타이머 동기화 전용 로켓배송 창구
    func sendTimerSyncToWatch(_ payload: [String: Any]) {
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        try? WCSession.default.updateApplicationContext(payload)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }
    
    private func saveBooksToAppGroup(_ books: [TimerStateManager.BookData], isFullSnapshot: Bool) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        var cached: [String: TimerStateManager.BookData] = [:]
        if !isFullSnapshot,
           let existingData = defaults.data(forKey: "books.data"),
           let existing = try? JSONDecoder().decode([TimerStateManager.BookData].self, from: existingData) {
            cached = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        }
        for book in books { cached[book.id] = book }
        let result = isFullSnapshot ? books : Array(cached.values)
        guard let data = try? JSONEncoder().encode(result) else { return }
        defaults.set(data, forKey: "books.data")
        WidgetCenter.shared.reloadTimelines(ofKind: AppGroupKey.homeWidgetKind)
    }
    
    private func sendCachedBooksIfNeeded() {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: "books.data"),
              let books = try? JSONDecoder().decode([TimerStateManager.BookData].self, from: data) else { return }
        sendBooksToWatch(books, isFullSnapshot: true)
    }
    
    func handleWatchMessage(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        
        if type == "sessionSaved" {
            print("📥 아이폰: 'sessionSaved' 이벤트 수신")
            handleSessionSaved(payload)
        }
        else if type == "bookUpdated" {
            print("📥 아이폰: 'bookUpdated' 이벤트 수신")
            handleBookUpdated(payload)
        }
        else if type == "timerCommand" {
            handleTimerCommand(payload)
        }
        else if type == "requestTimerState" {
            Task { @MainActor in
                ReadingTimerManager.shared.applyRemoteControl(.requestState)
            }
        }
        else if type == "requestBooks" {
            performWithContext { context in
                DispatchQueue.main.async {
                    let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
                    let books = (try? context.fetch(descriptor)) ?? []
                    self.sendBooksToWatch(
                        books.map { TimerStateManager.BookData.from($0) },
                        isFullSnapshot: true
                    )
                }
            }
        }
    }

    private func handleTimerCommand(_ payload: [String: Any]) {
        guard let data = payload["command"] as? Data,
              let command = try? JSONDecoder().decode(TimerSyncCommand.self, from: data),
              !handledCommandIDs.contains(command.id) else { return }

        handledCommandIDs.insert(command.id)
        if handledCommandIDs.count > 100 { handledCommandIDs.removeAll(keepingCapacity: true) }

        performWithContext { context in
            DispatchQueue.main.async {
                let manager = ReadingTimerManager.shared
                if command.action == .start,
                   manager.currentSession == nil,
                   let uuid = UUID(uuidString: command.bookID) {
                    let descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.id == uuid })
                    let book = try? context.fetch(descriptor).first
                    manager.applyRemoteControl(command.action, for: book)
                } else if manager.activeBookID?.uuidString == command.bookID || command.action == .requestState {
                    manager.applyRemoteControl(command.action)
                }
            }
        }
    }
    
    private func handleSessionSaved(_ payload: [String: Any]) {
        guard let sData = payload["session"] as? Data, let bData = payload["book"] as? Data,
              let sDict = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
              let uBook = try? JSONDecoder().decode(TimerStateManager.BookData.self, from: bData) else {
            print("❌ 아이폰: sessionSaved 페이로드 디코딩 실패")
            return
        }
        
        performWithContext { context in
            DispatchQueue.main.async {
                self.saveSessionToSwiftData(sessionDict: sDict, updatedBook: uBook, modelContext: context)
            }
        }
    }
    
    private func handleBookUpdated(_ payload: [String: Any]) {
        guard let bData = payload["book"] as? Data,
              let uBook = try? JSONDecoder().decode(TimerStateManager.BookData.self, from: bData) else {
            print("❌ 아이폰: bookUpdated 페이로드 디코딩 실패")
            return
        }
        
        performWithContext { context in
            DispatchQueue.main.async {
                self.updateBookInSwiftData(updatedBook: uBook, modelContext: context)
            }
        }
    }
    
    private func saveSessionToSwiftData(sessionDict: [String: Any], updatedBook: TimerStateManager.BookData, modelContext: ModelContext) {
        guard let idStr = sessionDict["bookID"] as? String, let bookID = UUID(uuidString: idStr),
              let startPage = sessionDict["startPage"] as? Int, let endPage = sessionDict["endPage"] as? Int,
              let duration = sessionDict["duration"] as? TimeInterval, let startInterval = sessionDict["startTime"] as? TimeInterval else {
            print("❌ 아이폰: saveSessionToSwiftData 파라미터 파싱 실패")
            return
        }
        
        let desc = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.id == bookID })
        guard let book = try? modelContext.fetch(desc).first else {
            print("❌ 아이폰: ID가 \(bookID)인 책을 DB에서 찾을 수 없습니다.")
            return
        }

        let startDate = Date(timeIntervalSince1970: startInterval)
        let receivedSessionID = (sessionDict["sessionID"] as? String).flatMap(UUID.init(uuidString:))
        let isDuplicate = book.sessions?.contains { existing in
            if let receivedSessionID, existing.id == receivedSessionID { return true }
            return existing.startTime == startDate
                && existing.startPage == startPage
                && existing.endPage == endPage
        } ?? false
        guard !isDuplicate else {
            ReadingTimerManager.shared.completeSessionFromWatch(bookID: idStr)
            print("ℹ️ iPhone: duplicate Watch session ignored")
            return
        }
        
        let session = ReadingSession(id: receivedSessionID ?? UUID(), startTime: startDate, startPage: startPage)
        session.finalize(endPage: endPage, measuredDuration: duration)
        
        book.addSession(session)
        modelContext.insert(session)
        book.currentPage = updatedBook.currentPage
        book.lastUpdated = updatedBook.lastUpdated
        book.checkCompletion()
        
        // ❌ 기존 독서 세션 캘린더 추가 로직 제거됨
        
        try? modelContext.save()
        ReadingTimerManager.shared.completeSessionFromWatch(bookID: idStr)
        let unit = (book.format == .ebook) ? "%" : "p"
        print("💾 아이폰: SwiftData에 독서 세션 및 페이지(\(endPage)\(unit)) 업데이트 성공!")
    }
    
    private func updateBookInSwiftData(updatedBook: TimerStateManager.BookData, modelContext: ModelContext) {
        guard let bookID = UUID(uuidString: updatedBook.id) else { return }
        let desc = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.id == bookID })
        guard let book = try? modelContext.fetch(desc).first else { return }
        
        book.currentPage = updatedBook.currentPage
        book.lastUpdated = updatedBook.lastUpdated
        book.checkCompletion()
        try? modelContext.save()
        let unit = (book.format == .ebook) ? "%" : "p"
        print("💾 아이폰: SwiftData에 책 페이지(\(updatedBook.currentPage)\(unit)) 업데이트 성공!")
    }
    
    func processPendingSessions() {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let sessions = defaults.array(forKey: "sessions.data") as? [[String: Any]],
              !sessions.isEmpty else { return }
        
        performWithContext { context in
            DispatchQueue.main.async {
                var processed = 0
                for sDict in sessions {
                    guard let idStr = sDict["bookID"] as? String, let bookID = UUID(uuidString: idStr),
                          let startPage = sDict["startPage"] as? Int, let endPage = sDict["endPage"] as? Int,
                          let duration = sDict["duration"] as? TimeInterval, let startInterval = sDict["startTime"] as? TimeInterval else { continue }
                    
                    let desc = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.id == bookID })
                    guard let book = try? context.fetch(desc).first else { continue }

                    let startDate = Date(timeIntervalSince1970: startInterval)
                    let receivedSessionID = (sDict["sessionID"] as? String).flatMap(UUID.init(uuidString:))
                    let isDuplicate = book.sessions?.contains { existing in
                        if let receivedSessionID, existing.id == receivedSessionID { return true }
                        return existing.startTime == startDate
                            && existing.startPage == startPage
                            && existing.endPage == endPage
                    } ?? false
                    guard !isDuplicate else { continue }
                    
                    let session = ReadingSession(id: receivedSessionID ?? UUID(), startTime: startDate, startPage: startPage)
                    session.finalize(endPage: endPage, measuredDuration: duration)
                    
                    book.addSession(session); book.currentPage = endPage; book.checkCompletion()
                    context.insert(session)
                    
                    // ❌ 기존 독서 세션 캘린더 추가 로직 제거됨
                    
                    processed += 1
                }
                
                if processed > 0 {
                    try? context.save()
                    defaults.removeObject(forKey: "sessions.data")
                    print("💾 아이폰: AppGroup에서 \(processed)개의 펜딩 세션 복구 및 저장 완료")
                }
            }
        }
    }
    
    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if state == .activated {
            isSessionActivated = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.sendCachedBooksIfNeeded()
            }
        }
    }
    func sessionDidBecomeInactive(_ s: WCSession) { isSessionActivated = false }
    func sessionDidDeactivate(_ s: WCSession) { isSessionActivated = false; WCSession.default.activate() }
    func sessionReachabilityDidChange(_ s: WCSession) { if s.isReachable { sendCachedBooksIfNeeded() } }
    
    func session(_ s: WCSession, didReceiveUserInfo u: [String: Any]) {
        print("📥 아이폰: didReceiveUserInfo 수신")
        DispatchQueue.main.async { self.handleWatchMessage(u) }
    }
    func session(_ s: WCSession, didReceiveMessage m: [String: Any]) {
        print("📥 아이폰: didReceiveMessage 수신")
        DispatchQueue.main.async { self.handleWatchMessage(m) }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async { self.handleWatchMessage(applicationContext) }
    }
}
