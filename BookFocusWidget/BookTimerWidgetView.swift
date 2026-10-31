// BookTimerWidgetView.swift
// ─────────────────────────────────────────────────────────────────────────────
// Widget Extension target ONLY.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Root View
struct BookTimerWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BookTimerEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                CircularView(entry: entry)
            case .accessoryRectangular:
                RectangularView(entry: entry)
            case .accessoryCorner:
                CornerView(entry: entry)
            case .accessoryInline:
                InlineView(entry: entry)
            default:
                CircularView(entry: entry)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Deep Link URL
private extension URL {
    static let bookFocusTimer = URL(string: "focusreader://timer")!
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - .accessoryCircular (원형 컴플리케이션)
// ─────────────────────────────────────────────────────────────────────────────
struct CircularView: View {
    let entry: BookTimerEntry
    private var state: WidgetTimerState { entry.state }
    private var progress: Double {
        guard state.totalPages > 0 else { return 0 }
        return min(Double(state.currentPage) / Double(state.totalPages), 1.0)
    }

    var body: some View {
        Button(intent: ToggleReadingTimerIntent(bookID: state.bookID ?? "")) {
            ZStack {
            if state.bookID != nil {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .widgetAccentable()

                VStack(spacing: 0) {
                    Image(systemName: state.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.bottom, 2)

                    if state.isRunning, let start = state.sessionStartDate {
                        Text(timerInterval: start.addingTimeInterval(-state.accumulatedElapsed)...Date.distantFuture, countsDown: false)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .minimumScaleFactor(0.7)
                    } else {
                        Text(formatElapsed(state.accumulatedElapsed))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                }
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                        .rotationEffect(.degrees(-5))
                        .padding(3)
                    
                    Image(systemName: "book")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        }
        .buttonStyle(.plain)
        .disabled(state.bookID == nil)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - .accessoryRectangular (직사각형 컴플리케이션)
// ─────────────────────────────────────────────────────────────────────────────
struct RectangularView: View {
    let entry: BookTimerEntry
    private var state: WidgetTimerState { entry.state }

    var body: some View {
        if state.bookID != nil {
            activeView
        } else {
            idleView
        }
    }

    private var activeView: some View {
        Button(intent: ToggleReadingTimerIntent(bookID: state.bookID ?? "")) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: state.isRunning ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .widgetAccentable()

                    Text(state.bookTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }

                if state.isRunning, let start = state.sessionStartDate {
                    Text(timerInterval: start.addingTimeInterval(-state.accumulatedElapsed)...Date.distantFuture, countsDown: false)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(formatElapsed(state.accumulatedElapsed))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.78))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(Color.white.opacity(0.9)).frame(width: geo.size.width * state.progress)
                    }
                }
                .frame(height: 4).padding(.vertical, 1)

                Text(state.isEbook ? "\((Double(state.currentPage) / 100).formatted(.percent.precision(.fractionLength(0)))) read" : "p. \(state.currentPage) of \(state.totalPages)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .buttonStyle(.plain)
    }

    private var idleView: some View {
        HStack(spacing: 10) {
            Image(systemName: "book")
                .font(.system(size: 16, weight: .light))
                .frame(width: 32, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .rotationEffect(.degrees(-3))
                )

            Text("bookfocus.")
                .font(.custom("ChalkboardSE-Bold", size: 18))
        }
        .foregroundStyle(.white.opacity(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .widgetURL(.bookFocusTimer)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - .accessoryCorner (코너 컴플리케이션)
// ─────────────────────────────────────────────────────────────────────────────
struct CornerView: View {
    let entry: BookTimerEntry
    private var state: WidgetTimerState { entry.state }

    var body: some View {
        Group {
            if state.bookID != nil {
                Image(systemName: state.isRunning ? "pencil" : "pause")
                    .font(.title3)
                    .widgetAccentable()
                    .widgetLabel {
                        if state.isRunning, let start = state.sessionStartDate {
                            Text(timerInterval: start.addingTimeInterval(-state.accumulatedElapsed)...Date.distantFuture, countsDown: false)
                        } else {
                            Text(formatElapsed(state.accumulatedElapsed))
                        }
                    }
            } else {
                Image(systemName: "book")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.5))
                    .widgetLabel {
                        Text("read").font(.custom("ChalkboardSE-Regular", size: 12))
                    }
            }
        }
        .widgetURL(.bookFocusTimer)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - .accessoryInline (인라인 컴플리케이션)
// ─────────────────────────────────────────────────────────────────────────────
struct InlineView: View {
    let entry: BookTimerEntry
    private var state: WidgetTimerState { entry.state }

    var body: some View {
        Group {
            if state.bookID != nil {
                Label {
                    if state.isRunning, let start = state.sessionStartDate {
                        Text(timerInterval: start.addingTimeInterval(-state.accumulatedElapsed)...Date.distantFuture, countsDown: false)
                    } else {
                        Text(formatElapsed(state.accumulatedElapsed))
                    }
                } icon: {
                    Image(systemName: state.isRunning ? "pencil" : "pause")
                }
            } else {
                Label {
                    Text("ready to read").font(.custom("ChalkboardSE-Regular", size: 12))
                } icon: {
                    Image(systemName: "book")
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .widgetURL(.bookFocusTimer)
    }
}

// MARK: - Helper
private func formatElapsed(_ interval: TimeInterval) -> String {
    let total = Int(interval)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}
