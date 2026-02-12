// FocusReaderWidget/AppIntent.swift
// ✅ 수정: 타이머 일시정지/재개 시 시간을 올바르게 계산

import WidgetKit
import AppIntents
import UIKit

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}

// MARK: - Timer Control Intents

/// 재생/일시정지 토글 Intent
struct ToggleTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Timer"
    static var description: IntentDescription = "Start or pause the reading timer"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = TimerStateManager.shared
        guard var state = manager.loadState() else {
            throw IntentError.noActiveSession
        }
        
        let now = Date()
        
        if state.isRunning {
            // ⭐ 일시정지: 현재까지의 경과 시간을 계산하여 저장
            if let startTime = state.sessionStartTime {
                let additionalTime = now.timeIntervalSince(startTime)
                state.pausedTime += additionalTime
                print("⏸ Widget Pause - Added time: \(additionalTime)s, Total paused: \(state.pausedTime)s")
            }
            state.isRunning = false
            state.sessionStartTime = nil  // ⭐ 중요: sessionStartTime 초기화
            
        } else {
            // ⭐ 재개: 새로운 시작 시간 설정
            state.isRunning = true
            state.sessionStartTime = now
            
            // ⭐ Timer Mode일 경우 남은 시간 재계산
            if state.isTimerMode {
                let totalTargetTime = TimeInterval(state.targetMinutes * 60)
                let remainingTime = max(0, totalTargetTime - state.pausedTime)
                state.timerEndDate = now.addingTimeInterval(remainingTime)
                print("▶️ Widget Resume (Timer Mode) - Remaining: \(remainingTime)s")
            } else {
                state.timerEndDate = nil
                print("▶️ Widget Resume (Stopwatch Mode)")
            }
        }
        
        // ⭐ elapsedTime도 업데이트 (일시정지 상태에서 표시용)
        state.elapsedTime = state.pausedTime
        
        // 상태 저장
        manager.saveState(state)
        
        // ⭐ 위젯 즉시 새로고침
        WidgetCenter.shared.reloadAllTimelines()
        
        // 앱에 상태 변경 알림 전송
        if let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader") {
            defaults.set("toggle", forKey: "widget.action")
            defaults.synchronize()
        }
        
        print("✅ Widget toggle completed - isRunning: \(state.isRunning), pausedTime: \(state.pausedTime)s")
        
        return .result()
    }
}

/// 타이머 정지 Intent (앱 열기)
struct StopTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Timer"
    static var description: IntentDescription = "Stop the reading timer and open the app"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = TimerStateManager.shared
        guard var state = manager.loadState() else {
            throw IntentError.noActiveSession
        }
        
        // ⭐ 실행 중이었다면 마지막 경과 시간 계산
        if state.isRunning, let startTime = state.sessionStartTime {
            let additionalTime = Date().timeIntervalSince(startTime)
            state.pausedTime += additionalTime
            state.elapsedTime = state.pausedTime
        }
        
        state.isRunning = false
        state.sessionStartTime = nil
        manager.saveState(state)
        
        // ⭐ 위젯 즉시 새로고침
        WidgetCenter.shared.reloadAllTimelines()
        
        // 앱에 정지 알림 전송
        if let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader") {
            defaults.set("stop", forKey: "widget.action")
            defaults.set(true, forKey: "widget.openEndPageInput")
            defaults.synchronize()
        }
        
        print("🛑 Widget stop completed")
        
        return .result()
    }
}

enum IntentError: Error, CustomStringConvertible {
    case noActiveSession
    
    var description: String {
        switch self {
        case .noActiveSession:
            return "No active reading session"
        }
    }
}
