import Foundation
import UserNotifications

enum WatchDueReminderScheduler {

    struct DueGroupPayload: Codable, Equatable {
        let dateKey: String
        let dueDate: Date
        let bookTitles: [String]
    }

    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional { return true }

        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch { return false }
    }

    static func scheduleGroup(_ payload: DueGroupPayload) async {
        guard await requestAuthorizationIfNeeded() else { return }
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

    static func cancelGroup(dateKey: String) {
        let ids = TimerLogic.dueReminderIdentifiers(dateKey: dateKey) + [
            "due-1d-\(dateKey)",
            "due-0d-\(dateKey)"
        ]
        
        let center = UNUserNotificationCenter.current()
        // 대기 중인 알림 취소
        center.removePendingNotificationRequests(withIdentifiers: ids)
        
        // 💡 해결 핵심 3: 이미 알림센터 화면에 배달되어 쌓여있는 중복 알림(Delivered)까지 싹 삭제
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func scheduleIfNeeded(id: String, dateKey: String, daysBefore: Int, bookTitles: [String], isToday: Bool) async {
        guard let components = TimerLogic.dueReminderComponents(dateKey: dateKey, daysBefore: daysBefore) else { return }
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        guard let nextDate = trigger.nextTriggerDate(), nextDate > Date() else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("book_return_reminder_title", comment: "")
        
        let prefix = NSLocalizedString(isToday ? "due_today_prefix" : "due_tomorrow_prefix", comment: "")
        let bookList = bookTitles.map { "• \($0)" }.joined(separator: "\n")

        content.body = "\(prefix)\n\(bookList)"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try? await center.add(request)
    }

}
