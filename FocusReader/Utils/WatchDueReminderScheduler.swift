import Foundation
import UserNotifications

public struct WatchDueReminderScheduler {

    public struct DueGroupPayload: Codable, Equatable {
        public let dateKey: String
        public let dueDate: Date
        public let bookTitles: [String]
    }

    @discardableResult
    public static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional { return true }

        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("[WatchDueReminderScheduler] Auth error:", error)
            return false
        }
    }

    public static func scheduleGroup(_ payload: DueGroupPayload) async {
        let granted = await requestAuthorizationIfNeeded()
        guard granted else { return }

        await removeLegacyTitleBasedReminders()

        let ids = TimerLogic.dueReminderIdentifiers(dateKey: payload.dateKey)

        cancelGroup(dateKey: payload.dateKey)

        guard !payload.bookTitles.isEmpty else { return }
        await scheduleIfNeeded(id: ids[0], dateKey: payload.dateKey, daysBefore: 1, bookTitles: payload.bookTitles, isToday: false)
        await scheduleIfNeeded(id: ids[1], dateKey: payload.dateKey, daysBefore: 0, bookTitles: payload.bookTitles, isToday: true)
    }

    private static func removeLegacyTitleBasedReminders() async {
        let center = UNUserNotificationCenter.current()
        let legacyIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("due-1d-") || $0.hasPrefix("due-0d-") }
        if !legacyIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: legacyIDs)
        }
        let deliveredLegacyIDs = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix("due-1d-") || $0.hasPrefix("due-0d-") }
        if !deliveredLegacyIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredLegacyIDs)
        }
    }

    public static func cancelGroup(dateKey: String) {
        let ids = TimerLogic.dueReminderIdentifiers(dateKey: dateKey) + [
            "due-1d-\(dateKey)",
            "due-0d-\(dateKey)"
        ]
        
        let center = UNUserNotificationCenter.current()
        // 💡 예약된(아직 안 울린) 알림 취소
        center.removePendingNotificationRequests(withIdentifiers: ids)
        
        // 💡 해결 핵심 2: 이미 사용자 화면에 떠서 쌓여있는(Delivered) 중복 알림까지 알림센터에서 깔끔하게 삭제
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func scheduleIfNeeded(
        id: String,
        dateKey: String,
        daysBefore: Int,
        bookTitles: [String],
        isToday: Bool
    ) async {
        guard let components = TimerLogic.dueReminderComponents(dateKey: dateKey, daysBefore: daysBefore) else { return }
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        guard let nextDate = trigger.nextTriggerDate(), nextDate > Date() else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("book_return_reminder_title", comment: "")

        let prefixKey = isToday ? "due_today_prefix" : "due_tomorrow_prefix"
        let prefix = NSLocalizedString(prefixKey, comment: "")
        
        let bookList = bookTitles.map { "• \($0)" }.joined(separator: "\n")

        content.body = "\(prefix)\n\(bookList)"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            print("[WatchDueReminderScheduler] Error:", error)
        }
    }

}
