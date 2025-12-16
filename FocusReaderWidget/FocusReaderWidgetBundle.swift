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
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.25))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {

                // Expanded - Leading
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .foregroundColor(.blue)
                        Text(context.attributes.bookTitle)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                }

                // Expanded - Trailing ✅ FIX
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isRunning {
                        if context.state.isTimerMode,
                           let endDate = context.state.timerEndDate {

                            let remaining = endDate.timeIntervalSince(Date())

                            if remaining > 0 {
                                Text(
                                    timerInterval: Date() ... endDate,
                                    countsDown: true
                                )
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .lineLimit(1)
                            } else {
                                Text("0:00")
                                    .foregroundColor(.red)
                            }

                        } else if let startDate = context.state.timerStartDate {
                            // 스톱워치 (카운트업)
                            Text(startDate, style: .timer)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    } else {
                        Text(formatPausedTime(context.state.pausedTime))
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                }

                // Expanded - Bottom (이미 정상)
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isTimerMode,
                       context.state.isRunning,
                       let startDate = context.state.timerStartDate,
                       let endDate = context.state.timerEndDate {

                        ProgressView(
                            timerInterval: startDate ... endDate,
                            countsDown: true
                        )
                        .tint(.blue)
                    }
                }

            } compactLeading: {
                Image(systemName: "book.fill")
                    .foregroundColor(.blue)
            }

            // Compact Trailing ✅ FIX
            compactTrailing: {
                if context.state.isRunning,
                   context.state.isTimerMode,
                   let endDate = context.state.timerEndDate {

                    let remaining = endDate.timeIntervalSince(Date())

                    if remaining > 0 {
                        Text(
                            timerInterval: Date() ... endDate,
                            countsDown: true
                        )
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    } else {
                        Text("0:00")
                            .foregroundColor(.red)
                    }

                } else if let startDate = context.state.timerStartDate {
                    Text(startDate, style: .timer)
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.semibold)
                } else {
                    Text(formatPausedTime(context.state.pausedTime))
                        .font(.system(.caption2, design: .monospaced))
                }
            }

            minimal: {
                Image(systemName: context.state.isRunning ? "timer" : "pause.circle.fill")
                    .foregroundColor(.blue)
            }
        }
    }

    private func formatPausedTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
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

            VStack(alignment: .leading) {
                Image(systemName: "book.fill")
                    .foregroundColor(.blue)
                Text(context.attributes.bookTitle)
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
        }
        .padding()
    }
    
    // MARK: - 통일된 시간 포맷팅
    private func formatPausedTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        // 1시간 이상: h:mm:ss
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        // 1시간 미만: m:ss
        else {
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
