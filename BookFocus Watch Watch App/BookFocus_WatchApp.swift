//
//  BookFocus_WatchApp.swift
//  BookFocus Watch Watch App
//

import SwiftUI

@main
struct BookFocus_Watch_Watch_AppApp: App {
    
    init() {
        // ✅ [수정] WCSession은 세션 매니저 내부에서 비동기 큐잉되도록 호출만 유지
        _ = WatchSessionManager.shared
        
        // ❌ [치명적 원인 제거] App.init()에서 알림 권한 XPC 비동기 호출 절대 금지
        // (알림 권한 요청은 ContentView가 완전히 렌더링된 이후로 이동시킴)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
