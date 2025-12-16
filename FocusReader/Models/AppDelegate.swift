import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // 🔥 알림 탭 감지를 위해 필수
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // 🔔 배너 / 알림을 눌렀을 때
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

        completionHandler()
    }
}
