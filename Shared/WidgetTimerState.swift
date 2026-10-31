import Foundation
import WidgetKit

enum AppGroupKey {
    static let suiteName = "group.com.Jaemin.FocusReader"
    static let homeWidgetKind = "com.Jaemin.FocusReader.HomeWidget"
    static let widgetState = "widget.active.timer"
    static let widgetAction = "widget.action"
    static let widgetActionBookID = "widget.action.bookID"
}

struct WidgetTimerState: Codable, Equatable {
    var bookID: String?
    var bookTitle: String
    var bookAuthor: String
    var currentPage: Int
    var totalPages: Int
    var sessionStartDate: Date?
    var accumulatedElapsed: TimeInterval
    var format: String?

    var isEbook: Bool { format == "ebook" || (format == nil && totalPages == 100) }
    var isRunning: Bool { sessionStartDate != nil }
    var progress: Double {
        guard totalPages > 0 else { return 0 }
        return min(max(Double(currentPage) / Double(totalPages), 0), 1)
    }
    var totalElapsed: TimeInterval {
        TimerLogic.elapsed(paused: accumulatedElapsed, segmentStartedAt: sessionStartDate)
    }

    init(
        bookID: String? = nil,
        bookTitle: String = "",
        bookAuthor: String = "",
        currentPage: Int = 0,
        totalPages: Int = 1,
        sessionStartDate: Date? = nil,
        accumulatedElapsed: TimeInterval = 0,
        format: String? = nil
    ) {
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.sessionStartDate = sessionStartDate
        self.accumulatedElapsed = accumulatedElapsed
        self.format = format
    }

    static let empty = WidgetTimerState()

    static func load() -> WidgetTimerState {
        guard let defaults = UserDefaults(suiteName: AppGroupKey.suiteName),
              let data = defaults.data(forKey: AppGroupKey.widgetState),
              let state = try? JSONDecoder().decode(WidgetTimerState.self, from: data) else {
            return .empty
        }
        return state
    }

    func save(reloadTimelines: Bool = true) {
        guard let defaults = UserDefaults(suiteName: AppGroupKey.suiteName),
              let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppGroupKey.widgetState)
        if reloadTimelines {
            WidgetCenter.shared.reloadTimelines(ofKind: "BookFocusTimerWidget")
        }
    }
}
