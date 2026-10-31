import Foundation

enum TimerLogic {
    static let completionNotificationID = "ReadingTimerEnd"

    static func elapsed(paused: TimeInterval, segmentStartedAt: Date?, now: Date = Date()) -> TimeInterval {
        guard let segmentStartedAt else { return max(0, paused) }
        return max(0, paused + now.timeIntervalSince(segmentStartedAt))
    }

    static func dueReminderIdentifiers(dateKey: String) -> [String] {
        ["due-\(dateKey)-1d", "due-\(dateKey)-0d"]
    }

    // The payload carries a calendar day, so syncing between time zones cannot shift the due day.
    // Leave timeZone unset: the notification follows the receiving device's local time.
    static func dueReminderComponents(dateKey: String, daysBefore: Int = 0, timeZone: TimeZone = .current) -> DateComponents? {
        let parts = dateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        guard let date = calendar.date(from: day),
              calendar.component(.year, from: date) == parts[0],
              calendar.component(.month, from: date) == parts[1],
              calendar.component(.day, from: date) == parts[2],
              let reminderDay = calendar.date(byAdding: .day, value: -daysBefore, to: date) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: reminderDay)
        components.hour = 9
        components.minute = 0
        components.second = 0
        return components
    }

}
