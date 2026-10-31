import SwiftUI
import SwiftData
import CoreData // 🔥 CloudKit 모니터링 알림 상수를 사용하기 위해 추가 필수
import OSLog

private struct StorageBootstrapResult {
    let container: ModelContainer
    let warningMessage: String?
}

private enum StorageBootstrap {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FocusReader",
        category: "StorageBootstrap"
    )

    static func makeContainer() -> StorageBootstrapResult {
        let schema = Schema([
            Book.self,
            ReadingSession.self,
            PageMemo.self,
        ])

        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [cloudConfiguration]
            )
            logger.info("SwiftData store opened with CloudKit")
            return StorageBootstrapResult(container: container, warningMessage: nil)
        } catch {
            logger.error("CloudKit store failed to open: \(error.localizedDescription, privacy: .public)")
        }

        // CloudKit 권한/계정 문제일 때는 같은 디스크 저장소를 로컬 모드로 먼저 재시도한다.
        let localConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [localConfiguration]
            )
            logger.warning("SwiftData store opened without CloudKit")
            return StorageBootstrapResult(container: container, warningMessage: nil)
        } catch {
            logger.error("Local store failed to open: \(error.localizedDescription, privacy: .public)")
        }

        // 기존 저장소가 손상되었거나 마이그레이션에 실패해도 삭제하지 않는다.
        // 별도의 영구 저장소로 실행하여 다음 업데이트에서 기존 데이터를 복구할 수 있게 한다.
        do {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let recoveryDirectory = applicationSupport.appendingPathComponent(
                "StorageRecovery",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: recoveryDirectory,
                withIntermediateDirectories: true
            )

            let recoveryConfiguration = ModelConfiguration(
                "Recovery",
                schema: schema,
                url: recoveryDirectory.appendingPathComponent("BookFocus.store"),
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: schema,
                configurations: [recoveryConfiguration]
            )
            logger.fault("Using the persistent recovery store")
            return StorageBootstrapResult(
                container: container,
                warningMessage: String(localized: "The app started in recovery mode because your reading data could not be opened. Your existing data has not been deleted.")
            )
        } catch {
            logger.fault("Persistent recovery store failed: \(error.localizedDescription, privacy: .public)")
        }

        // 파일 시스템 오류까지 발생한 경우에도 런칭 크래시는 방지한다.
        let memoryConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [memoryConfiguration]
            )
            logger.fault("Using an in-memory emergency store")
            return StorageBootstrapResult(
                container: container,
                warningMessage: String(localized: "The app started in temporary mode because data storage could not be opened. Data added during this session will not be saved after the app closes.")
            )
        } catch {
            // In-memory 저장소는 디스크·CloudKit을 사용하지 않으므로 스키마 자체가
            // 잘못된 경우에만 실패한다. 이 경우는 계속 실행할 안전한 방법이 없다.
            preconditionFailure("Invalid SwiftData schema: \(error)")
        }
    }
}

@main
struct FocusReaderApp: App {

    // 🔥 AppDelegate 연결
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var isStorageWarningPresented = false

    private let storage = StorageBootstrap.makeContainer()

    private var sharedModelContainer: ModelContainer { storage.container }
    
    // 🔥 앱 생명주기 초기화 (여기서 1회성 설정들을 보장)
    init() {
        // ⌚️ 워치 연동 시작: onAppear 대신 init에 두어 다중 창(iPad)에서도 1번만 실행되도록 보장
        WatchSyncManager.shared.start()
        
        // ☁️ 클라우드킷 모니터링 시작
        setupCloudKitMonitoring()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // ✅ [수정/추가됨] 앱 화면이 뜰 때 WatchSyncManager에 DB 컨텍스트를 주입합니다.
                // 이 코드가 실행되는 순간, 아까 만들어둔 WatchSyncManager의 didSet이 발동하여
                // 밀려있던 백그라운드 데이터(워치에서 온 타이머 정보 등)가 DB에 한꺼번에 저장됩니다!
                .onAppear {
                    WatchSyncManager.shared.modelContext = sharedModelContainer.mainContext
                }
                .task {
                    if storage.warningMessage != nil {
                        isStorageWarningPresented = true
                    }
                    await StoreKitManager.shared.updateCustomerProductStatus()
                    await AppOpenAdManager.shared.loadAd()
                    await AppOpenAdManager.shared.showAdIfAvailable()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await StoreKitManager.shared.updateCustomerProductStatus()
                        await AppOpenAdManager.shared.loadAd()
                        await AppOpenAdManager.shared.showAdIfAvailable()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .purchaseStatusChanged)) { _ in
                    if StoreKitManager.shared.isPremium {
                        AppOpenAdManager.shared.clearAdsAfterPurchase()
                    } else {
                        Task { await AppOpenAdManager.shared.loadAd() }
                    }
                }
                .alert(
                    "Data Storage Recovery",
                    isPresented: $isStorageWarningPresented
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(storage.warningMessage ?? "")
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // 🔥 CloudKit 동기화 모니터링
    private func setupCloudKitMonitoring() {
        // 1. 원격 저장소 변경 알림 (표준 상수 사용)
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { _ in
            print("☁️ iCloud 데이터 변경(RemoteChange) 감지됨")
        }

        // 2. CloudKit 컨테이너 이벤트 알림 (표준 상수 사용)
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            // userInfo에서 표준 키로 이벤트를 추출하여 정확한 에러 로깅
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            
            if let error = event.error {
                print("⚠️ CloudKit 동기화 에러 [\(event.type.rawValue)]: \(error.localizedDescription)")
            } else {
                // (선택 사항) 성공적인 동기화 이벤트 확인 시 주석 해제하여 테스트 가능
                // print("☁️ CloudKit 동기화 이벤트 완료: \(event.type.rawValue)")
            }
        }
    }
}
