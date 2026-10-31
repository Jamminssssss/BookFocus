import UIKit
import UserNotifications
import WatchConnectivity
import GoogleMobileAds

class AppDelegate: NSObject,
                   UIApplicationDelegate,
                   UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        UNUserNotificationCenter.current().delegate = self
        resetBadgeCount()
        if AdConfiguration.applicationID != nil {
            MobileAds.shared.start(completionHandler: nil)
        }

        return true
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

        resetBadgeCount()
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        resetBadgeCount()
        completionHandler([.banner, .sound])
    }
    
    // 🔥 [수정] 반복되는 배지 리셋 로직 통합
    private func resetBadgeCount() {
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { error in
                if let error = error {
                    print("Badge reset error: \(error)")
                }
            }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
}
