import ActivityKit
import WidgetKit
import SwiftUI

@main
struct FocusReaderWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadingTimerLiveActivity()
    }
}

// MARK: - Live Activity Widget
struct ReadingTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingTimerAttributes.self) { context in
            // 잠금화면 & 알림센터 (모든 기기)
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.25))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded - Leading
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.bookTitle)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        
                        Text("Page \(context.state.currentPage)/\(context.state.totalPages)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Expanded - Trailing
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if context.state.isRunning {
                            if context.state.isTimerMode,
                               let endDate = context.state.timerEndDate {
                                let remaining = endDate.timeIntervalSince(Date())

                                if remaining > 0 {
                                    Text(timerInterval: Date() ... endDate, countsDown: true)
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                        .foregroundColor(remaining < 60 ? .red : .primary)
                                } else {
                                    Text("0:00")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.red)
                                }
                            } else if let startDate = context.state.timerStartDate {
                                Text(startDate, style: .timer)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                        } else {
                            Text(formatPausedTime(context.state.pausedTime))
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.semibold)
                        }
                        
                        Text(context.state.isRunning ? "Reading..." : "Paused")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Expanded - Bottom
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isTimerMode,
                       context.state.isRunning,
                       let startDate = context.state.timerStartDate,
                       let endDate = context.state.timerEndDate {
                        ProgressView(timerInterval: startDate ... endDate, countsDown: true)
                            .tint(.blue)
                            .padding(.top, 8)
                    }
                }

            } compactLeading: {
                // Compact Leading
                HStack(spacing: 4) {
                    Image(systemName: context.state.isRunning ? "book.fill" : "pause.circle.fill")
                        .font(.caption2)
                    Text(context.attributes.bookTitle)
                        .font(.caption2)
                        .lineLimit(1)
                }
            } compactTrailing: {
                // Compact Trailing
                if context.state.isRunning {
                    if context.state.isTimerMode, let endDate = context.state.timerEndDate {
                        let remaining = endDate.timeIntervalSince(Date())
                        if remaining > 0 {
                            Text(timerInterval: Date() ... endDate, countsDown: true)
                                .font(.system(.caption2, design: .monospaced))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundColor(remaining < 60 ? .red : .primary)
                        } else {
                            Text("0:00")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    } else if let startDate = context.state.timerStartDate {
                        Text(startDate, style: .timer)
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                } else {
                    Text(formatPausedTime(context.state.pausedTime))
                        .font(.system(.caption2, design: .monospaced))
                }
            } minimal: {
                // Minimal
                Image(systemName: context.state.isRunning ? "timer" : "pause.circle.fill")
                    .foregroundColor(.blue)
            }
        }
    }

    private func formatPausedTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}


// MARK: - Lock Screen View
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<ReadingTimerAttributes>

    var body: some View {
        HStack(spacing: 12) {

            if context.state.isRunning,
               context.state.isTimerMode,
               let endDate = context.state.timerEndDate {

                let remaining = endDate.timeIntervalSince(Date())

                if remaining > 0 {
                    Text(
                        timerInterval: Date() ... endDate,
                        countsDown: true
                    )
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .foregroundColor(remaining < 60 ? .red : .white)
                    .monospacedDigit()
                } else {
                    Text("0:00")
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .foregroundColor(.red)
                }

            } else if let startDate = context.state.timerStartDate {
                Text(startDate, style: .timer)
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            } else {
                Text(formatPausedTime(context.state.pausedTime))
                    .font(.system(size: 32, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.bookTitle)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Text("Page \(context.state.currentPage) / \(context.state.totalPages)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding()
    }
    
    // MARK: - 통일된 시간 포맷팅
    private func formatPausedTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }


    
    private func shouldShowWarning(_ state: ReadingTimerAttributes.ContentState) -> Bool {
        guard state.isTimerMode,
              let endDate = state.timerEndDate else { return false }
        
        let remaining = endDate.timeIntervalSince(Date())
        return remaining < 60 && remaining > 0
    }
}
