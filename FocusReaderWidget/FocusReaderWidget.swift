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
        
        // 현재 시간 계산
        if state.isRunning, let startDate = state.sessionStartTime {
            let now = Date()
            let elapsed = now.timeIntervalSince(startDate)
            state.elapsedTime = state.pausedTime + elapsed
        }
        
        let currentDate = Date()
        var entries: [TimerEntry] = []
        
        // 1분마다 업데이트되는 타임라인 생성 (다음 5분)
        for minuteOffset in 0..<5 {
            if let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate) {
                var entryState = state
                
                // 실행 중이면 경과 시간 업데이트
                if state.isRunning, let startDate = state.sessionStartTime {
                    let elapsed = entryDate.timeIntervalSince(startDate)
                    entryState.elapsedTime = state.pausedTime + elapsed
                }
                
                entries.append(TimerEntry(date: entryDate, timerState: entryState))
            }
        }
        
        // 다음 업데이트 정책: 실행 중이면 1분마다, 아니면 더 길게
        let policy: TimelineReloadPolicy = state.isRunning ? .after(Calendar.current.date(byAdding: .minute, value: 1, to: currentDate)!) : .after(Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)!)
        
        let timeline = Timeline(entries: entries, policy: policy)
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
                // 책 이름
                Text(entry.timerState.bookTitle)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                
                // 페이지
                Text("Page \(entry.timerState.currentPage)/\(entry.timerState.totalPages)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                // 경과 시간
                Text(formatTime(entry.timerState.elapsedTime))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(entry.timerState.isRunning ? .primary : .secondary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "book.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("타이머를\n시작하세요")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer(minLength: 4)
            
            // 재생/일시정지 버튼
            Button(intent: ToggleTimerIntent()) {
                VStack(spacing: 2) {
                    Image(systemName: entry.timerState.isRunning ? "pause.fill" : "play.fill")
                        .font(.title3)
                    Text(entry.timerState.isRunning ? "일시정지" : "재생")
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
            // 왼쪽: 정보
            VStack(alignment: .leading, spacing: 8) {
                // 현재 시간
                Text(entry.date, style: .time)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                if !entry.timerState.bookTitle.isEmpty {
                    // 책 이름
                    Text(entry.timerState.bookTitle)
                        .font(.headline)
                        .lineLimit(2)
                    
                    // 페이지
                    Text("Page \(entry.timerState.currentPage) / \(entry.timerState.totalPages)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // 경과 시간
                    Text(formatTime(entry.timerState.elapsedTime))
                        .font(.system(.title2, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(entry.timerState.isRunning ? .primary : .secondary)
                } else {
                    Text("타이머를 시작하세요")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("앱에서 책을 선택하고\n타이머를 시작하세요")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            
            Spacer()
            
            // 오른쪽: 재생/일시정지 버튼
            Button(intent: ToggleTimerIntent()) {
                VStack(spacing: 6) {
                    Image(systemName: entry.timerState.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                    Text(entry.timerState.isRunning ? "일시정지" : "재생")
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
            // 현재 시간
            Text(entry.date, style: .time)
                .font(.title)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            if !entry.timerState.bookTitle.isEmpty {
                // 책 정보
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
                
                // 경과 시간
                Text(formatTime(entry.timerState.elapsedTime))
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(entry.timerState.isRunning ? .primary : .secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    Text("타이머를 시작하세요")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    Text("앱에서 책을 선택하고\n타이머를 시작하세요")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
            
            // 재생/일시정지 버튼
            Button(intent: ToggleTimerIntent()) {
                HStack(spacing: 12) {
                    Image(systemName: entry.timerState.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                    Text(entry.timerState.isRunning ? "일시정지" : "재생")
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

// MARK: - Helper
private func formatTime(_ time: TimeInterval) -> String {
    let h = Int(time) / 3600
    let m = Int(time) / 60 % 60
    let s = Int(time) % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%d:%02d", m, s)
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
