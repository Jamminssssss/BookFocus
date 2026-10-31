// BookFocusTimerWidget.swift
// ─────────────────────────────────────────────────────────────────────────────
// Widget Extension target ONLY.
// ─────────────────────────────────────────────────────────────────────────────

import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct BookTimerEntry: TimelineEntry {
    let date: Date
    let state: WidgetTimerState
}

// MARK: - Timeline Provider

struct BookTimerProvider: TimelineProvider {

    func placeholder(in context: Context) -> BookTimerEntry {
        BookTimerEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (BookTimerEntry) -> Void) {
        let state = WidgetTimerState.load()
        completion(BookTimerEntry(date: Date(), state: state))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BookTimerEntry>) -> Void) {
        let state = WidgetTimerState.load()
        let now = Date()
        let policy: TimelineReloadPolicy = state.isRunning
            ? .after(now.addingTimeInterval(21_600))
            : .never
        completion(Timeline(entries: [BookTimerEntry(date: now, state: state)], policy: policy))
    }
}

// MARK: - Placeholder helper

private extension WidgetTimerState {
    static let placeholder = WidgetTimerState(
        bookID: "preview",
        bookTitle: "데미안",
        bookAuthor: "헤르만 헤세",
        currentPage: 128,
        totalPages: 256,
        sessionStartDate: Date().addingTimeInterval(-754),
        accumulatedElapsed: 0,
        format: nil
    )
}

// MARK: - Widget Definition

@main
struct BookFocusTimerWidget: Widget {
    let kind = "BookFocusTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BookTimerProvider()) { entry in
            BookTimerWidgetView(entry: entry)
        }
        .configurationDisplayName("BookFocus Timer")
        .description("독서 타이머 상태를 워치 페이스에 표시합니다")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}
