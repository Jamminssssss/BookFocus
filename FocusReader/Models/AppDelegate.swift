// FocusReader/Models/AppDelegate.swift
import UIKit
import UserNotifications
import WatchConnectivity

class AppDelegate: NSObject,
                   UIApplicationDelegate,
                   UNUserNotificationCenterDelegate {  // ✅ WCSessionDelegate 제거

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

        // ⌚️ WatchConnectivity는 WatchSyncManager.start()에서 처리
        // (더 이상 여기서 activate하지 않음)

        return true
    }

    // ✅ WCSessionDelegate 메서드들 모두 제거
    // WatchSyncManager가 이제 처리합니다

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
