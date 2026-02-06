import UIKit
import UserNotifications
import WatchConnectivity

class AppDelegate: NSObject,
                   UIApplicationDelegate,
                   UNUserNotificationCenterDelegate,
                   WCSessionDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // 🔔 알림 delegate
        UNUserNotificationCenter.current().delegate = self

        // 🔥 iOS 17 이상: 배지 제거
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { error in
                if let error = error {
                    print("Badge reset error: \(error)")
                }
            }
        } else {
            application.applicationIconBadgeNumber = 0
        }

        // ⌚️ WatchConnectivity 활성화
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            print("✅ WCSession activated")
        }

        return true
    }

    // MARK: - WatchConnectivity Delegate (필수)

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            print("❌ WCSession activation error:", error.localizedDescription)
        } else {
            print("⌚️ WCSession state:", activationState.rawValue)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    
    // 📥 Watch → iOS (백그라운드)
    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        WatchSyncManager.shared.handleWatchMessage(userInfo)
    }
    
    // 📥 Watch → iOS (즉시)
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        WatchSyncManager.shared.handleWatchMessage(message)
    }

    // MARK: - Notification Handling

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if userInfo["type"] as? String == "timerCompleted" {
            NotificationCenter.default.post(
                name: NSNotification.Name("TimerCompletedFromNotification"),
                object: nil
            )
        }

        // 🔥 배지 제거
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 🔥 배지 제거
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }

        completionHandler([.banner, .sound])
    }
}
