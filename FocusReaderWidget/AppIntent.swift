//
//  AppIntent.swift
//  FocusReaderWidget
//
//  Created by JeaminPark on 12/12/25.
//

import WidgetKit
import AppIntents
import UIKit

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    // An example configurable parameter.
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
        
        state.isRunning.toggle()
        manager.saveState(state)
        
        // 앱에 상태 변경 알림 전송 (UserDefaults 사용)
        if let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader") {
            defaults.set("toggle", forKey: "widget.action")
            defaults.synchronize()
        }
        
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
        
        state.isRunning = false
        manager.saveState(state)
        
        // 앱에 정지 알림 전송 (UserDefaults 사용)
        if let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader") {
            defaults.set("stop", forKey: "widget.action")
            // 딥링크 플래그 설정
            defaults.set(true, forKey: "widget.openEndPageInput")
            defaults.synchronize()
        }
        
        // 앱 열기 요청 (iOS 17+ 에서는 openApp 사용 가능). URL은 UserDefaults 플래그로 앱에서 처리.
        // Note: IntentResult has no `openApp()` API. We rely on the UserDefaults flag for the host app to open/navigate as needed.
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

