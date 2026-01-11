//
//  TimerStateManager.swift
//  FocusReader
//
//  Created for widget integration
//

import Foundation
import WidgetKit

/// AppGroup을 통한 타이머 상태 공유 매니저
/// 위젯과 앱 간의 타이머 상태를 동기화합니다
class TimerStateManager {
    static let shared = TimerStateManager()
    
    // TODO: 실제 앱그룹 ID로 변경 필요 (사용자가 설정한 값)
    private let appGroupID = "group.com.Jaemin.FocusReader"
    private var userDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
    
    private init() {}
    
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
        
        // 위젯 새로고침 요청
        WidgetCenter.shared.reloadTimelines(ofKind: "FocusReaderWidget")
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
        
        var state = TimerState(
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
    
    // MARK: - Clear State
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
        
        defaults.synchronize()
        
        // 위젯 새로고침 요청
        WidgetCenter.shared.reloadTimelines(ofKind: "FocusReaderWidget")
    }
    
    // MARK: - Update Running State
    func updateRunningState(_ isRunning: Bool) {
        guard let defaults = userDefaults else { return }
        defaults.set(isRunning, forKey: Keys.isRunning)
        defaults.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "FocusReaderWidget")
    }
}
