import SwiftUI
import SwiftData

@main
struct FocusReaderApp: App {

    // 🔥 AppDelegate 연결
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Book.self,
            ReadingSession.self,
            PageMemo.self,
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            setupCloudKitMonitoring()
            print("✅ ModelContainer 생성 완료 (iCloud 동기화 활성화)")
            return container
        } catch {
            print("❌ ModelContainer 생성 실패: \(error.localizedDescription)")
            fatalError("Could not create ModelContainer")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // ⌚️ 워치 연동 시작 (🔥 이게 핵심)
                    WatchSyncManager.shared.start()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // 🔥 CloudKit 동기화 모니터링
    private static func setupCloudKitMonitoring() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSPersistentStoreRemoteChange"),
            object: nil,
            queue: .main
        ) { _ in
            print("☁️ iCloud 동기화 이벤트 발생")
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSPersistentCloudKitContainerEventChangedNotification"),
            object: nil,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?["error"] as? Error {
                print("⚠️ CloudKit 동기화 에러: \(error.localizedDescription)")
            }
        }
    }
}
