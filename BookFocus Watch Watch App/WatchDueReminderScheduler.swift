import Foundation
import UserNotifications

/// Scheduler for watchOS due reminders - Group notifications by date
enum WatchDueReminderScheduler {

    // MARK: - Payload (날짜 기준 그룹)
    struct DueGroupPayload: Codable, Equatable {
        let dateKey: String      // yyyy-MM-dd
        let dueDate: Date
        let bookTitles: [String]
    }

    // MARK: - Authorization

    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .authorized {
            return true
        }

        do {
            return try await center.requestAuthorization(
                options: [.alert, .badge, .sound]
            )
        } catch {
            print("❌ [WatchDueReminderScheduler] Auth error:", error)
            return false
        }
    }

    // MARK: - Public (Group Schedule)

    static func scheduleGroup(_ payload: DueGroupPayload) async {
        let granted = await requestAuthorizationIfNeeded()
        guard granted else {
            print("❌ [WatchDueReminderScheduler] Notification not permitted")
            return
        }

        // 같은 날짜 기존 알림 제거
        cancelGroup(dateKey: payload.dateKey)

        let calendar = Calendar.current

        // 🔔 전날
        let minus1Day = calendar.date(byAdding: .day, value: -1, to: payload.dueDate)
        await scheduleIfNeeded(
            id: "due-\(payload.dateKey)-1d",
            fireDate: minus1Day,
            bookTitles: payload.bookTitles,
            isToday: false
        )

        // 🔔 당일
        await scheduleIfNeeded(
            id: "due-\(payload.dateKey)-0d",
            fireDate: payload.dueDate,
            bookTitles: payload.bookTitles,
            isToday: true
        )
    }

    static func cancelGroup(dateKey: String) {
        let ids = [
            "due-\(dateKey)-1d",
            "due-\(dateKey)-0d"
        ]

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)
        
        print("⌚️🔕 [WatchDueReminderScheduler] Cancelled group: \(dateKey)")
    }

    // MARK: - Private

    private static func scheduleIfNeeded(
        id: String,
        fireDate: Date?,
        bookTitles: [String],
        isToday: Bool
    ) async {
        guard let fireDate else { return }

        let center = UNUserNotificationCenter.current()
        let scheduledDate = normalizeToNineAM(fireDate)

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString(
            "book_return_reminder_title",
            comment: "Notification title for book due reminder"
        )

        let prefixKey = isToday
            ? "due_today_prefix"
            : "due_tomorrow_prefix"

        let prefix = NSLocalizedString(prefixKey, comment: "")
        let bookList = bookTitles
            .map { "• \($0)" }
            .joined(separator: "\n")

        content.body = "\(prefix)\n\(bookList)"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: scheduledDate
        )

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: comps,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            print("⌚️🔔 [WatchDueReminderScheduler] Scheduled:", id, scheduledDate)
        } catch {
            print("❌ [WatchDueReminderScheduler] Error:", error)
        }
    }

    private static func normalizeToNineAM(_ date: Date) -> Date {
        var comps = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: date
        )
        comps.hour = 9
        comps.minute = 0
        comps.second = 0
        return Calendar.current.date(from: comps) ?? date
    }
}
