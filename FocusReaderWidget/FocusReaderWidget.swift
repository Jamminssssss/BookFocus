//
//  FocusReaderWidget.swift
//  FocusReaderWidget
//
//  Created by JeaminPark on 12/12/25.
//

import WidgetKit
import SwiftUI
import AppIntents

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry {
        TimerEntry(
            date: Date(),
            timerState: TimerStateManager.TimerState(
                isRunning: false,
                bookTitle: "Sample Book",
                currentPage: 50,
                totalPages: 300,
                elapsedTime: 0,
                sessionStartTime: nil,
                pausedTime: 0,
                isTimerMode: false,
                targetMinutes: 30,
                timerEndDate: nil,
                bookID: nil
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> ()) {
        let manager = TimerStateManager.shared
        let state = manager.loadState() ?? TimerStateManager.TimerState(
            isRunning: false,
            bookTitle: "",
            currentPage: 0,
            totalPages: 0,
            elapsedTime: 0,
            sessionStartTime: nil,
            pausedTime: 0,
            isTimerMode: false,
            targetMinutes: 30,
            timerEndDate: nil,
            bookID: nil
        )
        
        let entry = TimerEntry(date: Date(), timerState: state)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> ()) {
        let manager = TimerStateManager.shared
        let state = manager.loadState() ?? TimerStateManager.TimerState(
            isRunning: false,
            bookTitle: "",
            currentPage: 0,
            totalPages: 0,
            elapsedTime: 0,
            sessionStartTime: nil,
            pausedTime: 0,
            isTimerMode: false,
            targetMinutes: 30,
            timerEndDate: nil,
            bookID: nil
        )
        
        let currentDate = Date()
        let entry = TimerEntry(date: currentDate, timerState: state)
        
        // Update more frequently when running (every 15 seconds), otherwise every hour
        let nextUpdate = state.isRunning
            ? Calendar.current.date(byAdding: .second, value: 15, to: currentDate)!
            : Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct TimerEntry: TimelineEntry {
    let date: Date
    let timerState: TimerStateManager.TimerState
}

struct FocusReaderWidgetEntryView : View {
    var entry: TimerEntry
    @Environment(\.widgetFamily) var widgetFamily
    
    var body: some View {
        switch widgetFamily {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget
struct SmallWidgetView: View {
    let entry: TimerEntry
    
    var body: some View {
        VStack(spacing: 6) {
            if !entry.timerState.bookTitle.isEmpty {
                // Book title
                Text(entry.timerState.bookTitle)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                
                // Page info
                Text("Page \(entry.timerState.currentPage)/\(entry.timerState.totalPages)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                // Timer display - Real-time update
                TimerDisplayView(
                    isRunning: entry.timerState.isRunning,
                    sessionStartTime: entry.timerState.sessionStartTime,
                    pausedTime: entry.timerState.pausedTime,
                    isTimerMode: entry.timerState.isTimerMode,
                    timerEndDate: entry.timerState.timerEndDate,
                    fontSize: 20
                )
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "book.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Start\nTimer")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer(minLength: 4)
            
            // Play/Pause button
            Button(intent: ToggleTimerIntent()) {
                VStack(spacing: 2) {
                    Image(systemName: entry.timerState.isRunning ? "pause.fill" : "play.fill")
                        .font(.title3)
                    Text(entry.timerState.isRunning ? "Pause" : "Play")
                        .font(.system(size: 10))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(entry.timerState.isRunning ? Color.orange : Color.green)
                .cornerRadius(8)
            }
            .buttonStyle(.borderless)
            .disabled(entry.timerState.bookTitle.isEmpty)
            .opacity(entry.timerState.bookTitle.isEmpty ? 0.5 : 1.0)
        }
        .padding(12)
    }
}

// MARK: - Medium Widget
struct MediumWidgetView: View {
    let entry: TimerEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Left: Information
            VStack(alignment: .leading, spacing: 8) {
                // Current time
               
                
                if !entry.timerState.bookTitle.isEmpty {
                    // Book title
                    Text(entry.timerState.bookTitle)
                        .font(.headline)
                        .lineLimit(2)
                    
                    // Page info
                    Text("Page \(entry.timerState.currentPage) / \(entry.timerState.totalPages)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Timer display - Real-time update
                    TimerDisplayView(
                        isRunning: entry.timerState.isRunning,
                        sessionStartTime: entry.timerState.sessionStartTime,
                        pausedTime: entry.timerState.pausedTime,
                        isTimerMode: entry.timerState.isTimerMode,
                        timerEndDate: entry.timerState.timerEndDate,
                        fontSize: 28
                    )
                } else {
                    Text("Start Timer")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Select a book in the app\nand start the timer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            
            Spacer()
            
            // Right: Play/Pause button
            Button(intent: ToggleTimerIntent()) {
                VStack(spacing: 6) {
                    Image(systemName: entry.timerState.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                    Text(entry.timerState.isRunning ? "Pause" : "Play")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .frame(width: 100, height: 100)
                .background(entry.timerState.isRunning ? Color.orange : Color.green)
                .cornerRadius(16)
            }
            .buttonStyle(.borderless)
            .disabled(entry.timerState.bookTitle.isEmpty)
            .opacity(entry.timerState.bookTitle.isEmpty ? 0.5 : 1.0)
        }
        .padding()
    }
}

// MARK: - Large Widget
struct LargeWidgetView: View {
    let entry: TimerEntry
    
    var body: some View {
        VStack(spacing: 20) {
            // Current time
           
            
            if !entry.timerState.bookTitle.isEmpty {
                // Book info
                VStack(spacing: 8) {
                    Text(entry.timerState.bookTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    
                    Text("Page \(entry.timerState.currentPage) / \(entry.timerState.totalPages)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                // Timer display - Real-time update
                TimerDisplayView(
                    isRunning: entry.timerState.isRunning,
                    sessionStartTime: entry.timerState.sessionStartTime,
                    pausedTime: entry.timerState.pausedTime,
                    isTimerMode: entry.timerState.isTimerMode,
                    timerEndDate: entry.timerState.timerEndDate,
                    fontSize: 48
                )
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    Text("Start Timer")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    Text("Select a book in the app\nand start the timer")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
            
            // Play/Pause button
            Button(intent: ToggleTimerIntent()) {
                HStack(spacing: 12) {
                    Image(systemName: entry.timerState.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                    Text(entry.timerState.isRunning ? "Pause" : "Play")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(entry.timerState.isRunning ? Color.orange : Color.green)
                .cornerRadius(16)
            }
            .buttonStyle(.borderless)
            .disabled(entry.timerState.bookTitle.isEmpty)
            .opacity(entry.timerState.bookTitle.isEmpty ? 0.5 : 1.0)
        }
        .padding()
    }
}

// MARK: - Timer Display View (Real-time update)
struct TimerDisplayView: View {
    let isRunning: Bool
    let sessionStartTime: Date?
    let pausedTime: TimeInterval
    let isTimerMode: Bool
    let timerEndDate: Date?
    let fontSize: CGFloat
    
    var body: some View {
        if isRunning {
            if isTimerMode, let endDate = timerEndDate {
                // Timer mode: Countdown
                let remaining = endDate.timeIntervalSince(Date())
                
                if remaining > 0 {
                    Text(timerInterval: Date() ... endDate, countsDown: true)
                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(remaining < 60 ? .red : .primary)
                        .monospacedDigit()
                } else {
                    // Timer finished
                    Text("0:00")
                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                        .monospacedDigit()
                }
            } else if let startDate = sessionStartTime {
                // Stopwatch mode: Counts up from start time
                let adjustedStartDate = startDate.addingTimeInterval(-pausedTime)
                
                Text(adjustedStartDate, style: .timer)
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .monospacedDigit()
            }
        } else {
            // Paused: Display fixed time
            Text(formatTime(pausedTime))
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let h = Int(time) / 3600
        let m = Int(time) / 60 % 60
        let s = Int(time) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

struct FocusReaderWidget: Widget {
    let kind: String = "FocusReaderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            FocusReaderWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Reading Timer")
        .description("Control your reading timer from the widget")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    FocusReaderWidget()
} timeline: {
    TimerEntry(
        date: .now,
        timerState: TimerStateManager.TimerState(
            isRunning: true,
            bookTitle: "Sample Book",
            currentPage: 50,
            totalPages: 300,
            elapsedTime: 1234,
            sessionStartTime: Date().addingTimeInterval(-1234),
            pausedTime: 0,
            isTimerMode: false,
            targetMinutes: 30,
            timerEndDate: nil,
            bookID: nil
        )
    )
}
