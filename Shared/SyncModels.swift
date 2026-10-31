import Foundation

enum TimerSyncAction: String, Codable {
    case start
    case pause
    case stop
    case cancel
    case requestState
}

struct TimerSyncCommand: Codable, Equatable {
    var id: UUID
    var action: TimerSyncAction
    var bookID: String
    var sentAt: Date

    init(action: TimerSyncAction, bookID: String, sentAt: Date = Date()) {
        self.id = UUID()
        self.action = action
        self.bookID = bookID
        self.sentAt = sentAt
    }
}

/// iPhone, widget, and Watch targets must encode exactly the same timer payload.
struct SharedTimerState: Codable, Equatable {
    var isRunning: Bool
    var bookTitle: String
    var currentPage: Int
    var totalPages: Int
    var elapsedTime: TimeInterval
    var sessionStartTime: Date?
    var pausedTime: TimeInterval
    var isTimerMode: Bool
    var targetMinutes: Int
    var targetSeconds: Int?
    var timerEndDate: Date?
    var bookID: String?
    var format: String?
    var startPage: Int?
    var sessionOriginalStartTime: Date?
    var lastUpdated: Date?
    var sourceDevice: String?

    var hasActiveSession: Bool {
        bookID != nil && (
            isRunning
                || elapsedTime > 0
                || pausedTime > 0
                || sessionStartTime != nil
                || sessionOriginalStartTime != nil
                || startPage != nil
        )
    }

    var isEbook: Bool { format == "ebook" || (format == nil && totalPages == 100) }

    init(
        isRunning: Bool,
        bookTitle: String,
        currentPage: Int,
        totalPages: Int,
        elapsedTime: TimeInterval,
        sessionStartTime: Date?,
        pausedTime: TimeInterval,
        isTimerMode: Bool,
        targetMinutes: Int,
        targetSeconds: Int? = nil,
        timerEndDate: Date?,
        bookID: String?,
        format: String? = nil,
        startPage: Int? = nil,
        sessionOriginalStartTime: Date? = nil,
        lastUpdated: Date? = nil,
        sourceDevice: String? = nil
    ) {
        self.isRunning = isRunning
        self.bookTitle = bookTitle
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.elapsedTime = elapsedTime
        self.sessionStartTime = sessionStartTime
        self.pausedTime = pausedTime
        self.isTimerMode = isTimerMode
        self.targetMinutes = targetMinutes
        self.targetSeconds = targetSeconds
        self.timerEndDate = timerEndDate
        self.bookID = bookID
        self.format = format
        self.startPage = startPage
        self.sessionOriginalStartTime = sessionOriginalStartTime
        self.lastUpdated = lastUpdated
        self.sourceDevice = sourceDevice
    }

    mutating func toggleRunningState(now: Date = Date(), source: String) {
        if isRunning {
            let measuredElapsed = TimerLogic.elapsed(
                paused: pausedTime,
                segmentStartedAt: sessionStartTime,
                now: now
            )
            isRunning = false
            sessionStartTime = nil
            pausedTime = measuredElapsed
            elapsedTime = measuredElapsed
        } else {
            isRunning = true
            sessionStartTime = now
            elapsedTime = pausedTime

            if isTimerMode {
                let configuredSeconds = TimeInterval(targetSeconds ?? targetMinutes * 60)
                timerEndDate = now.addingTimeInterval(max(0, configuredSeconds - pausedTime))
            }
        }

        lastUpdated = now
        sourceDevice = source
    }
}

struct SharedBookData: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var author: String
    var totalPages: Int
    var currentPage: Int
    var createdAt: Date
    var lastUpdated: Date
    var checkoutDate: Date?
    var dueDate: Date?
    var format: String?
    var loanStatus: String?

    var isEbook: Bool { format == "ebook" || (format == nil && totalPages == 100) }
    var isReturned: Bool { loanStatus == "returned" }
    var isRenewed: Bool { loanStatus == "renewed" }

    var dueMinus1DayAtNine: Date? {
        guard let dueDate else { return nil }
        let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: dueDate) ?? dueDate
        return nineAMLocal(on: previousDay)
    }

    var dueDayAtNine: Date? {
        dueDate.map(nineAMLocal(on:))
    }

    private func nineAMLocal(on date: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = 9
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? date
    }
}
