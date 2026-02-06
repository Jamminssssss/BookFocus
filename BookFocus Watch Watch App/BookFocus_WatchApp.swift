//
//  BookFocus_WatchApp.swift
//  BookFocus Watch Watch App
//
//  Created by JeaminPark on 1/11/26.
//

import SwiftUI

@main
struct BookFocus_Watch_Watch_AppApp: App {
    
    init() {
        // WatchSessionManager 초기화 (자동으로 activate)
        _ = WatchSessionManager.shared
        
        // 알림 권한 요청
        Task {
            _ = await WatchDueReminderScheduler.requestAuthorizationIfNeeded()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

