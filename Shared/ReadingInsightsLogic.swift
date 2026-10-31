import Foundation

public struct ReadingInsightSession: Equatable, Sendable {
    public let startTime: Date
    public let duration: TimeInterval

    public init(startTime: Date, duration: TimeInterval) {
        self.startTime = startTime
        self.duration = max(0, duration)
    }
}

public struct DailyReadingMetric: Identifiable, Equatable, Sendable {
    public var id: Date { day }
    public let day: Date
    public let duration: TimeInterval
    public let sessionCount: Int

    public init(day: Date, duration: TimeInterval, sessionCount: Int) {
        self.day = day
        self.duration = duration
        self.sessionCount = sessionCount
    }
}

public enum ReadingInsightsLogic {
    public static func dailyMetrics(
        sessions: [ReadingInsightSession],
        numberOfDays: Int,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [DailyReadingMetric] {
        guard numberOfDays > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -(numberOfDays - 1), to: today) ?? today
        let grouped = Dictionary(grouping: sessions.filter { $0.duration > 0 }) {
            calendar.startOfDay(for: $0.startTime)
        }

        return (0..<numberOfDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            let matches = grouped[day] ?? []
            return DailyReadingMetric(
                day: day,
                duration: matches.reduce(0) { $0 + $1.duration },
                sessionCount: matches.count
            )
        }
    }

    public static func currentStreak(
        sessions: [ReadingInsightSession],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Int {
        let activeDays = Set(sessions.filter { $0.duration > 0 }.map { calendar.startOfDay(for: $0.startTime) })
        guard !activeDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        var cursor = activeDays.contains(today)
            ? today
            : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var streak = 0

        while activeDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    public static func averageDuration(_ sessions: [ReadingInsightSession]) -> TimeInterval {
        let completed = sessions.filter { $0.duration > 0 }
        guard !completed.isEmpty else { return 0 }
        return completed.reduce(0) { $0 + $1.duration } / Double(completed.count)
    }

    public static func longestDuration(_ sessions: [ReadingInsightSession]) -> TimeInterval {
        sessions.map(\.duration).max() ?? 0
    }

    public static func mostActiveWeekday(
        _ sessions: [ReadingInsightSession],
        calendar: Calendar = .current
    ) -> Int? {
        let completed = sessions.filter { $0.duration > 0 }
        guard !completed.isEmpty else { return nil }
        let totals = Dictionary(grouping: completed) { calendar.component(.weekday, from: $0.startTime) }
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
        return totals.max { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key > rhs.key }
            return lhs.value < rhs.value
        }?.key
    }
}
