//
//  TimerStateManager.swift
//  FocusReader
//

import Foundation
import WidgetKit

class TimerStateManager {
    static let shared = TimerStateManager()
    private let appGroupID = "group.com.Jaemin.FocusReader"
    private var userDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }
    
    private let statesMapKey = "timer.states.map"
    private let activeBookIDKey = "timer.activeBookID"
    private let controlWidgetKind = "com.Jaemin.FocusReader.FocusReaderWidget"
    private let homeWidgetKind = AppGroupKey.homeWidgetKind
    
    private init() {}
    
    typealias TimerState = SharedTimerState
    
    // MARK: - App Interactors (메인 앱과의 통신을 위한 메서드)
    
    /// 특정 책의 상태만 콕 집어서 불러옵니다.
    func loadState(forBookID bookID: String) -> TimerState? {
        return loadAllStatesMap()[bookID]
    }
    
    /// 특정 책을 위젯의 '현재 활성 책'으로 강제 지정합니다.
    func setActiveBookID(_ bookID: String, reloadWidget: Bool = true) {
        userDefaults?.set(bookID, forKey: activeBookIDKey)
        if reloadWidget {
            WidgetCenter.shared.reloadTimelines(ofKind: controlWidgetKind)
            WidgetCenter.shared.reloadTimelines(ofKind: homeWidgetKind)
        }
    }
    
    // MARK: - Save State (동기식 I/O 병목 해제 및 reloadWidget 지원)
    func saveState(_ state: TimerState, reloadWidget: Bool = true) {
        // 💡 bookID가 둘 다 없을 때 조용히 리턴되어 버리는 버그 방지
        let resolvedBookID = state.bookID ?? userDefaults?.string(forKey: activeBookIDKey) ?? UUID().uuidString
        guard let defaults = userDefaults else { return }
        
        var map = loadAllStatesMap()
        var updated = state
        updated.bookID = resolvedBookID
        map[resolvedBookID] = updated
        
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: statesMapKey)
            defaults.set(resolvedBookID, forKey: activeBookIDKey) // 저장되는 책을 즉시 Active로 갱신
        }
        
        if reloadWidget {
            WidgetCenter.shared.reloadTimelines(ofKind: controlWidgetKind)
            WidgetCenter.shared.reloadTimelines(ofKind: homeWidgetKind)
        }
    }
    
    func saveStateAsync(_ state: TimerState, reloadWidget: Bool = true) async {
        saveState(state, reloadWidget: reloadWidget)
    }
    
    // MARK: - Load State
    func loadState() -> TimerState? { loadActiveState() }
    
    func loadActiveState() -> TimerState? {
        let map = loadAllStatesMap()
        let activeID = userDefaults?.string(forKey: activeBookIDKey)
        
        // Active ID가 맵에 명확히 존재할 때만 반환
        if let id = activeID, let state = map[id] {
            return state
        }
        
        // 만약 activeID가 없거나 데이터가 꼬였다면, 맵에서 임의의 책 하나를 Active 상태로 복구
        if let firstState = map.values.first, let firstID = firstState.bookID {
            userDefaults?.set(firstID, forKey: activeBookIDKey)
            return firstState
        }
        
        return nil
    }
    
    private func loadAllStatesMap() -> [String: TimerState] {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: statesMapKey),
              let map = try? JSONDecoder().decode([String: TimerState].self, from: data) else { return [:] }
        return map
    }
    
    // MARK: - Clear State
    func clearState() {
        guard let bookID = userDefaults?.string(forKey: activeBookIDKey),
              let defaults = userDefaults else { return }
        
        var map = loadAllStatesMap()
        map.removeValue(forKey: bookID)
        
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: statesMapKey)
        }
        defaults.removeObject(forKey: activeBookIDKey)
        
        WidgetCenter.shared.reloadTimelines(ofKind: controlWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: homeWidgetKind)
    }
    
    /// 타이머 종료 시 잔존 상태를 확실히 지우기 위한 메서드
    func clearActiveState() {
        guard let defaults = userDefaults else { return }
        defaults.removeObject(forKey: activeBookIDKey)
        defaults.removeObject(forKey: statesMapKey)
        WidgetCenter.shared.reloadTimelines(ofKind: controlWidgetKind)
        WidgetCenter.shared.reloadTimelines(ofKind: homeWidgetKind)
    }
    
    func updateRunningState(_ isRunning: Bool) {
        guard var state = loadActiveState() else { return }
        state.isRunning = isRunning
        saveState(state)
    }
    
    // MARK: - Book Data & Management
    // ⭐️ Equatable 프로토콜 추가로 배열 비교 및 뷰 업데이트 최적화 보장
    typealias BookData = SharedBookData
    
    func saveBooks(_ books: [BookData]) {
        if let encoded = try? JSONEncoder().encode(books) {
            userDefaults?.set(encoded, forKey: "books.data")
            WidgetCenter.shared.reloadTimelines(ofKind: homeWidgetKind)
        }
    }
    func loadBooks() -> [BookData] {
        guard let data = userDefaults?.data(forKey: "books.data"),
              let books = try? JSONDecoder().decode([BookData].self, from: data) else { return [] }
        return books
    }
    func updateBook(_ book: BookData) {
        var books = loadBooks()
        if let index = books.firstIndex(where: { $0.id == book.id }) { books[index] = book }
        else { books.append(book) }
        saveBooks(books)
    }
    
    func getAction() -> String? {
        guard let defaults = userDefaults,
              let action = defaults.string(forKey: "watch.pendingAction") else { return nil }
        defaults.removeObject(forKey: "watch.pendingAction")
        return action
    }
    
    func getWidgetAction() -> String? {
        guard let defaults = userDefaults,
              let action = defaults.string(forKey: "widget.action") else { return nil }
        defaults.removeObject(forKey: "widget.action")
        return action
    }
    
    // MARK: - Cover Image (앱 그룹 공유 컨테이너에 파일로 저장)
    private var coverImagesDirectory: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        let dir = containerURL.appendingPathComponent("CoverImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    func saveCoverImage(_ data: Data, forBookID bookID: String) {
        guard let fileURL = coverImagesDirectory?.appendingPathComponent(bookID) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    
    func loadCoverImage(forBookID bookID: String?) -> Data? {
        guard let bookID, let fileURL = coverImagesDirectory?.appendingPathComponent(bookID) else { return nil }
        return try? Data(contentsOf: fileURL)
    }
    
    func deleteCoverImage(forBookID bookID: String) {
        guard let fileURL = coverImagesDirectory?.appendingPathComponent(bookID) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension SharedBookData {
    static func from(_ book: Book) -> SharedBookData {
        SharedBookData(
            id: book.id.uuidString,
            title: book.title,
            author: book.author,
            totalPages: book.totalPages,
            currentPage: book.currentPage,
            createdAt: book.createdAt,
            lastUpdated: book.lastUpdated,
            checkoutDate: book.checkoutDate,
            dueDate: book.dueDate,
            format: book.formatRawValue,
            loanStatus: book.loanStatusRawValue
        )
    }
}
