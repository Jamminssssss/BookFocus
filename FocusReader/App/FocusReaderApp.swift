//
//  FocusReaderApp.swift
//  FocusReader
//
//  Created by JeaminPark on 12/10/25.
//

import SwiftUI
import SwiftData

@main
struct FocusReaderApp: App {

    // 🔥 1️⃣ AppDelegate 연결
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Book.self,
            ReadingSession.self,
            PageMemo.self,
        ])
        
        // ✅ iCloud 동기화 설정 추가
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic  // 🔥 iCloud 동기화 활성화
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // 🔥 동기화 이벤트 모니터링 설정
            setupCloudKitMonitoring()
            
            print("✅ ModelContainer 생성 완료 (iCloud 동기화 활성화)")
            return container
            
        } catch {
            // 🔥 더 상세한 에러 로깅
            print("❌ ModelContainer 생성 실패: \(error.localizedDescription)")
            
            // CloudKit 관련 에러인지 확인
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain)")
                print("Error code: \(nsError.code)")
                print("Error info: \(nsError.userInfo)")
            }
            
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
    
    // 🔥 CloudKit 동기화 모니터링
    private static func setupCloudKitMonitoring() {
        // 동기화 시작 알림
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSPersistentStoreRemoteChange"),
            object: nil,
            queue: .main
        ) { notification in
            print("☁️ iCloud 동기화 이벤트 발생")
            
            if let userInfo = notification.userInfo {
                print("📦 동기화 상세 정보: \(userInfo)")
            }
        }
        
        // 동기화 에러 모니터링 (선택사항)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSPersistentCloudKitContainerEventChangedNotification"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let error = userInfo["error"] as? Error {
                print("⚠️ CloudKit 동기화 에러: \(error.localizedDescription)")
            }
        }
    }
}
