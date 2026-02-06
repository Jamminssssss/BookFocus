//
//  TimerStateManager.swift
//  BookFocus Watch Watch App
//
//  Shared state manager for watch and app
//

import Foundation

/// AppGroup을 통한 타이머 상태 공유 매니저
/// 워치와 앱 간의 타이머 상태를 동기화합니다
class TimerStateManager {
    static let shared = TimerStateManager()
    
    private let appGroupID = "group.com.Jaemin.FocusReader"
    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
    
    private init() {}
    
    func clearState() {
          guard let defaults = userDefaults else { return }

          defaults.removeObject(forKey: Keys.isRunning)
          defaults.removeObject(forKey: Keys.bookTitle)
          defaults.removeObject(forKey: Keys.currentPage)
          defaults.removeObject(forKey: Keys.totalPages)
          defaults.removeObject(forKey: Keys.elapsedTime)
          defaults.removeObject(forKey: Keys.sessionStartTime)
          defaults.removeObject(forKey: Keys.pausedTime)
          defaults.removeObject(forKey: Keys.isTimerMode)
          defaults.removeObject(forKey: Keys.targetMinutes)
          defaults.removeObject(forKey: Keys.timerEndDate)
          defaults.removeObject(forKey: Keys.bookID)
      }
    
    // MARK: - Keys
    private enum Keys {
        static let isRunning = "timer.isRunning"
        static let bookTitle = "timer.bookTitle"
        static let currentPage = "timer.currentPage"
        static let totalPages = "timer.totalPages"
        static let elapsedTime = "timer.elapsedTime"
        static let sessionStartTime = "timer.sessionStartTime"
        static let pausedTime = "timer.pausedTime"
        static let isTimerMode = "timer.isTimerMode"
        static let targetMinutes = "timer.targetMinutes"
        static let timerEndDate = "timer.timerEndDate"
        static let bookID = "timer.bookID"
        
        // Books list
        static let booksData = "books.data"
    }
    
    // MARK: - State Structure
    struct TimerState: Codable {
        var isRunning: Bool
        var bookTitle: String
        var currentPage: Int
        var totalPages: Int
        var elapsedTime: TimeInterval
        var sessionStartTime: Date?
        var pausedTime: TimeInterval
        var isTimerMode: Bool
        var targetMinutes: Int
        var timerEndDate: Date?
        var bookID: String?
        
        var hasActiveSession: Bool {
            return elapsedTime > 0 || sessionStartTime != nil
        }
    }
    
    // MARK: - Book Structure (for watch)
    struct BookData: Codable, Identifiable {
        var id: String
        var title: String
        var author: String
        var totalPages: Int
        var currentPage: Int
        var createdAt: Date
        var lastUpdated: Date
        
        // 🔥 추가: 반납일 정보
        var checkoutDate: Date?
        var dueDate: Date?
        
        // 🔥 추가: 반납일 알림 계산 프로퍼티
        var dueMinus1DayAtNine: Date? {
            guard let due = dueDate else { return nil }
            let d = Calendar.current.date(byAdding: .day, value: -1, to: due) ?? due
            return nineAMLocal(on: d)
        }
        
        var dueDayAtNine: Date? {
            guard let due = dueDate else { return nil }
            return nineAMLocal(on: due)
        }
        
        private func nineAMLocal(on date: Date) -> Date {
            var cal = Calendar.current
            cal.timeZone = .current
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            var nine = DateComponents()
            nine.year = comps.year
            nine.month = comps.month
            nine.day = comps.day
            nine.hour = 9
            nine.minute = 0
            nine.second = 0
            return cal.date(from: nine) ?? date
        }
    }
    
    // MARK: - Save State
    func saveState(_ state: TimerState) {
        guard let defaults = userDefaults else {
            print("❌ TimerStateManager: AppGroup UserDefaults를 생성할 수 없습니다")
            return
        }
        
        defaults.set(state.isRunning, forKey: Keys.isRunning)
        defaults.set(state.bookTitle, forKey: Keys.bookTitle)
        defaults.set(state.currentPage, forKey: Keys.currentPage)
        defaults.set(state.totalPages, forKey: Keys.totalPages)
        defaults.set(state.elapsedTime, forKey: Keys.elapsedTime)
        defaults.set(state.pausedTime, forKey: Keys.pausedTime)
        defaults.set(state.isTimerMode, forKey: Keys.isTimerMode)
        defaults.set(state.targetMinutes, forKey: Keys.targetMinutes)
        defaults.set(state.bookID, forKey: Keys.bookID)
        
        if let sessionStartTime = state.sessionStartTime {
            defaults.set(sessionStartTime, forKey: Keys.sessionStartTime)
        } else {
            defaults.removeObject(forKey: Keys.sessionStartTime)
        }
        
        if let timerEndDate = state.timerEndDate {
            defaults.set(timerEndDate, forKey: Keys.timerEndDate)
        } else {
            defaults.removeObject(forKey: Keys.timerEndDate)
        }
        
        defaults.synchronize()
    }
    
    // MARK: - Load State
    func loadState() -> TimerState? {
        guard let defaults = userDefaults else {
            print("❌ TimerStateManager: AppGroup UserDefaults를 읽을 수 없습니다")
            return nil
        }
        
        guard defaults.object(forKey: Keys.bookTitle) != nil else {
            return nil
        }
        
        let state = TimerState(
            isRunning: defaults.bool(forKey: Keys.isRunning),
            bookTitle: defaults.string(forKey: Keys.bookTitle) ?? "",
            currentPage: defaults.integer(forKey: Keys.currentPage),
            totalPages: defaults.integer(forKey: Keys.totalPages),
            elapsedTime: defaults.double(forKey: Keys.elapsedTime),
            sessionStartTime: defaults.object(forKey: Keys.sessionStartTime) as? Date,
            pausedTime: defaults.double(forKey: Keys.pausedTime),
            isTimerMode: defaults.bool(forKey: Keys.isTimerMode),
            targetMinutes: defaults.integer(forKey: Keys.targetMinutes),
            timerEndDate: defaults.object(forKey: Keys.timerEndDate) as? Date,
            bookID: defaults.string(forKey: Keys.bookID)
        )
        
        return state
    }
    
    // MARK: - Books Management
    func saveBooks(_ books: [BookData]) {
        guard let defaults = userDefaults else { return }
        
        if let encoded = try? JSONEncoder().encode(books) {
            defaults.set(encoded, forKey: Keys.booksData)
            defaults.synchronize()
        }
    }
    
    func loadBooks() -> [BookData] {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: Keys.booksData),
              let books = try? JSONDecoder().decode([BookData].self, from: data) else {
            return []
        }
        return books
    }
    
    func updateBook(_ book: BookData) {
        var books = loadBooks()
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            books[index] = book
        } else {
            books.append(book)
        }
        saveBooks(books)
    }
    
    // MARK: - Update Running State
    func updateRunningState(_ isRunning: Bool) {
        guard let defaults = userDefaults else { return }
        defaults.set(isRunning, forKey: Keys.isRunning)
        defaults.synchronize()
    }
    
    // MARK: - Action Flags
    func setAction(_ action: String) {
        guard let defaults = userDefaults else { return }
        defaults.set(action, forKey: "watch.action")
        defaults.synchronize()
    }
    
    func getAction() -> String? {
        guard let defaults = userDefaults else { return nil }
        let action = defaults.string(forKey: "watch.action")
        defaults.removeObject(forKey: "watch.action")
        defaults.synchronize()
        return action
    }
}
