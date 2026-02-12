// FocusReaderWidget/FocusReaderWidget.swift
// ✅ 수정: 타임라인 업데이트 주기를 짧게 하여 실시간성 개선

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
        var state = manager.loadState() ?? TimerStateManager.TimerState(
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
        
        // ⭐ 실행 중일 때 현재 경과 시간 계산
        if state.isRunning, let startTime = state.sessionStartTime {
            let currentElapsed = state.pausedTime + currentDate.timeIntervalSince(startTime)
            state.elapsedTime = currentElapsed
        } else {
            // 일시정지 상태에서는 pausedTime 사용
            state.elapsedTime = state.pausedTime
        }
        
        let entry = TimerEntry(date: currentDate, timerState: state)
        
        // ⭐ 업데이트 주기 최적화
        let nextUpdate: Date
        if state.isRunning {
            // 실행 중: 1초마다 업데이트 (iOS는 최소 1초 간격 지원)
            nextUpdate = Calendar.current.date(byAdding: .second, value: 1, to: currentDate)!
        } else if state.pausedTime > 0 {
            // 일시정지 상태: 10초마다 (배터리 절약)
            nextUpdate = Calendar.current.date(byAdding: .second, value: 10, to: currentDate)!
        } else {
            // 타이머 없음: 1시간마다
            nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!
        }
        
        // ⭐ .atEnd 정책 사용: 다음 업데이트 시간이 되면 자동으로 새로고침
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
                Text(entry.timerState.bookTitle)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                
                Text("Page \(entry.timerState.currentPage)/\(entry.timerState.totalPages)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
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
            VStack(alignment: .leading, spacing: 8) {
                if !entry.timerState.bookTitle.isEmpty {
                    Text(entry.timerState.bookTitle)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text("Page \(entry.timerState.currentPage) / \(entry.timerState.totalPages)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
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
            if !entry.timerState.bookTitle.isEmpty {
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
            // ⭐ Paused: Display fixed time from pausedTime
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
