import AppIntents
import Foundation

struct ToggleReadingTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause Reading Timer"
    static let description = IntentDescription("Controls the active BookFocus timer from your watch face.")
    static let openAppWhenRun = true

    @Parameter(title: "Book ID")
    var bookID: String

    init() {
        bookID = ""
    }

    init(bookID: String) {
        self.bookID = bookID
    }

    func perform() async throws -> some IntentResult {
        let state = WidgetTimerState.load()
        guard !bookID.isEmpty, state.bookID == bookID,
              let defaults = UserDefaults(suiteName: AppGroupKey.suiteName) else {
            return .result()
        }

        let action: TimerSyncAction = state.isRunning ? .pause : .start
        defaults.set(action.rawValue, forKey: AppGroupKey.widgetAction)
        defaults.set(bookID, forKey: AppGroupKey.widgetActionBookID)
        return .result()
    }
}
