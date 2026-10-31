import AppIntents
import SwiftUI
import UIKit
import WidgetKit

struct HomeReadingEntry: TimelineEntry {
    let date: Date
    let timerState: SharedTimerState?
    let recentBook: SharedBookData?
    let coverImageData: Data?
}

struct HomeReadingProvider: TimelineProvider {
    private var previewEntry: HomeReadingEntry {
        HomeReadingEntry(
            date: Date(),
            timerState: SharedTimerState(
                isRunning: true,
                bookTitle: "데미안",
                currentPage: 128,
                totalPages: 256,
                elapsedTime: 754,
                sessionStartTime: Date().addingTimeInterval(-754),
                pausedTime: 0,
                isTimerMode: false,
                targetMinutes: 30,
                timerEndDate: nil,
                bookID: "preview"
            ),
            recentBook: nil,
            coverImageData: nil
        )
    }

    func placeholder(in context: Context) -> HomeReadingEntry {
        previewEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeReadingEntry) -> Void) {
        completion(context.isPreview ? previewEntry : makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeReadingEntry>) -> Void) {
        let entry = makeEntry()
        let refreshDate = Date().addingTimeInterval(entry.timerState?.isRunning == true ? 3_600 : 10_800)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func makeEntry() -> HomeReadingEntry {
        let manager = TimerStateManager.shared
        let activeState = manager.loadActiveState().flatMap { $0.hasActiveSession ? $0 : nil }
        let books = manager.loadBooks()
        let activeBook = activeState.flatMap { state in
            books.first { $0.id == state.bookID }
        }
        let recentBook = activeBook ?? books.max { $0.lastUpdated < $1.lastUpdated }
        let coverData = manager.loadCoverImage(forBookID: activeState?.bookID ?? recentBook?.id)

        return HomeReadingEntry(
            date: Date(),
            timerState: activeState,
            recentBook: recentBook,
            coverImageData: coverData
        )
    }
}

struct FocusReaderHomeWidget: Widget {
    static let kind = AppGroupKey.homeWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: HomeReadingProvider()) { entry in
            FocusReaderHomeWidgetView(entry: entry)
        }
        .configurationDisplayName("BookFocus")
        .description("독서 타이머와 현재 책의 진행 상황을 홈 화면에서 확인하세요.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct FocusReaderHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: HomeReadingEntry

    private var paperColor: Color {
        colorScheme == .dark
            ? Color(red: 0.07, green: 0.07, blue: 0.065)
            : Color(red: 0.98, green: 0.97, blue: 0.94)
    }
    private var inkColor: Color {
        colorScheme == .dark
            ? Color(red: 0.96, green: 0.95, blue: 0.90)
            : Color(red: 0.12, green: 0.11, blue: 0.09)
    }

    var body: some View {
        Group {
            if let timerState = entry.timerState {
                activeTimerView(timerState)
            } else if let book = entry.recentBook {
                recentBookView(book)
            } else {
                emptyView
            }
        }
        .padding(family == .systemSmall ? 14 : 16)
        .foregroundStyle(inkColor)
        .containerBackground(for: .widget) { paperBackground }
        .widgetURL(URL(string: "focusreader://timer"))
    }

    @ViewBuilder
    private func activeTimerView(_ state: SharedTimerState) -> some View {
        if family == .systemMedium {
            HStack(spacing: 16) {
                coverView.frame(width: 76)
                timerDetails(state, compact: false)
            }
        } else {
            timerDetails(state, compact: true)
        }
    }

    private func timerDetails(_ state: SharedTimerState, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            brandHeader(status: state.isRunning ? "reading" : "paused")
            Text(state.bookTitle)
                .font(.custom("ChalkboardSE-Bold", size: compact ? 17 : 19))
                .lineLimit(1)
            timerText(state)
                .font(.system(size: compact ? 24 : 29, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
            progressBar(progress: progress(current: state.currentPage, total: state.totalPages))
            HStack(spacing: 8) {
                Text(progressLabel(current: state.currentPage, total: state.totalPages, isEbook: state.isEbook))
                    .font(.custom("ChalkboardSE-Regular", size: 11))
                    .foregroundStyle(inkColor.opacity(0.58))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(intent: ToggleHomeReadingTimerIntent(bookID: state.bookID ?? "")) {
                    Image(systemName: state.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 30, height: 26)
                        .foregroundStyle(paperColor)
                        .background(inkColor, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(state.bookID == nil)
                .accessibilityLabel(state.isRunning ? "Pause reading timer" : "Resume reading timer")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func recentBookView(_ book: SharedBookData) -> some View {
        if family == .systemMedium {
            HStack(spacing: 16) {
                coverView.frame(width: 76)
                VStack(alignment: .leading, spacing: 9) {
                    brandHeader(status: "ready")
                    Spacer(minLength: 0)
                    Text(book.title)
                        .font(.custom("ChalkboardSE-Bold", size: 20))
                        .lineLimit(2)
                    Text(book.author.isEmpty ? "your next chapter is waiting" : book.author)
                        .font(.custom("ChalkboardSE-Regular", size: 12))
                        .foregroundStyle(inkColor.opacity(0.58))
                        .lineLimit(1)
                    progressBar(progress: bookProgress(book))
                    Text("tap to continue · \(progressLabel(for: book))")
                        .font(.custom("ChalkboardSE-Regular", size: 11))
                        .foregroundStyle(inkColor.opacity(0.58))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 9) {
                brandHeader(status: "ready")
                Spacer(minLength: 0)
                Text(book.title)
                    .font(.custom("ChalkboardSE-Bold", size: 18))
                    .lineLimit(2)
                progressBar(progress: bookProgress(book))
                Text(progressLabel(for: book))
                    .font(.custom("ChalkboardSE-Regular", size: 11))
                    .foregroundStyle(inkColor.opacity(0.58))
            }
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            brandHeader(status: "ready")
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 27, weight: .light))
                .frame(width: 48, height: 58)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(inkColor.opacity(0.65), style: StrokeStyle(lineWidth: 1.4, dash: [5, 3]))
                        .rotationEffect(.degrees(-3))
                }
            Text("your next chapter\nstarts here.")
                .font(.custom("ChalkboardSE-Bold", size: 17))
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func brandHeader(status: String) -> some View {
        HStack(spacing: 5) {
            Text("bookfocus.")
                .font(.custom("ChalkboardSE-Bold", size: 13))
            Spacer()
            Circle()
                .fill(inkColor.opacity(status == "reading" ? 0.9 : 0.28))
                .frame(width: 6, height: 6)
            Text(status)
                .font(.custom("ChalkboardSE-Regular", size: 10))
                .foregroundStyle(inkColor.opacity(0.58))
        }
    }

    private var coverView: some View {
        Group {
            if let data = entry.coverImageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    inkColor.opacity(0.055)
                    Image(systemName: "book.closed")
                        .font(.system(size: 24, weight: .light))
                }
            }
        }
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(inkColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                .rotationEffect(.degrees(-1.5))
        }
    }

    private var paperBackground: some View {
        ZStack {
            paperColor
            RoundedRectangle(cornerRadius: 20)
                .stroke(inkColor.opacity(0.16), lineWidth: 1)
                .padding(5)
        }
    }

    private func progressBar(progress: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(inkColor.opacity(0.11))
                Capsule().fill(inkColor.opacity(0.78))
                    .frame(width: max(4, geometry.size.width * progress))
            }
        }
        .frame(height: 5)
    }

    @ViewBuilder
    private func timerText(_ state: SharedTimerState) -> some View {
        if state.isRunning, let start = state.sessionStartTime {
            if state.isTimerMode, let end = state.timerEndDate {
                Text(timerInterval: start.addingTimeInterval(-state.pausedTime)...max(end, Date().addingTimeInterval(1)), countsDown: true)
            } else {
                Text(timerInterval: start.addingTimeInterval(-state.pausedTime)...Date.distantFuture, countsDown: false)
            }
        } else {
            Text(formatElapsed(state.pausedTime))
        }
    }

    private func bookProgress(_ book: SharedBookData) -> Double {
        progress(current: book.currentPage, total: book.totalPages)
    }

    private func progress(current: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(current) / Double(total), 0), 1)
    }

    private func progressLabel(for book: SharedBookData) -> String {
        progressLabel(current: book.currentPage, total: book.totalPages, isEbook: book.isEbook)
    }

    private func progressLabel(current: Int, total: Int, isEbook: Bool) -> String {
        isEbook ? "\((Double(current) / 100).formatted(.percent.precision(.fractionLength(0)))) read" : "p. \(current) of \(total)"
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}

struct ToggleHomeReadingTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or resume reading"
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Book ID")
    var bookID: String

    init() {}

    init(bookID: String) {
        self.bookID = bookID
    }

    func perform() async throws -> some IntentResult {
        guard var state = TimerStateManager.shared.loadState(forBookID: bookID), state.hasActiveSession else {
            return .result()
        }

        state.toggleRunningState(source: "homeWidget")
        TimerStateManager.shared.saveState(state)
        if let defaults = UserDefaults(suiteName: AppGroupKey.suiteName) {
            defaults.set("toggle", forKey: AppGroupKey.widgetAction)
            defaults.set(bookID, forKey: AppGroupKey.widgetActionBookID)
        }
        return .result()
    }
}
