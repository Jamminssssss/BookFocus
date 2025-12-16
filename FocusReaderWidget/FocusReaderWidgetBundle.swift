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
            // 잠금 화면 UI
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
                
                // Expanded - Trailing
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isRunning, let startDate = context.state.timerStartDate {
                        if context.state.isTimerMode, let endDate = context.state.timerEndDate {
                            // 카운트다운 타이머
                            let remaining = endDate.timeIntervalSince(Date())
                            Group {
                                if remaining > 0 {
                                    // 진행 중 - 실시간 카운트다운
                                    Text(endDate, style: .timer)
                                } else {
                                    // 완료 - 고정 텍스트
                                    Text("0:00")
                                        .foregroundColor(.red)
                                }
                            }
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        } else {
                            // 스톱워치
                            Text(startDate, style: .timer)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                        }
                    } else {
                        Text(formatPausedTime(context.state.pausedTime))
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                }
                
                // Expanded - Bottom
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isTimerMode,
                       context.state.isRunning,
                       let startDate = context.state.timerStartDate,
                       let endDate = context.state.timerEndDate {
                        let remaining = endDate.timeIntervalSince(Date())
                        if remaining > 0 {
                            ProgressView(timerInterval: startDate...endDate, countsDown: true)
                                .tint(.blue)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "book.fill")
                    .foregroundColor(.blue)
            } compactTrailing: {
                if context.state.isRunning, let startDate = context.state.timerStartDate {
                    if context.state.isTimerMode, let endDate = context.state.timerEndDate {
                        // 카운트다운 타이머
                        let remaining = endDate.timeIntervalSince(Date())
                        Group {
                            if remaining > 0 {
                                // 진행 중 - 실시간 카운트다운
                                Text(endDate, style: .timer)
                            } else {
                                // 완료 - 고정 텍스트
                                Text("0:00")
                                    .foregroundColor(.red)
                            }
                        }
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                    } else {
                        Text(startDate, style: .timer)
                            .font(.system(.caption2, design: .monospaced))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                    }
                } else {
                    Text(formatPausedTime(context.state.pausedTime))
                        .font(.system(.caption2, design: .monospaced))
                        .fontWeight(.semibold)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                }
            } minimal: {
                Image(systemName: context.state.isRunning ? "timer" : "pause.circle.fill")
                    .foregroundColor(.blue)
            }
        }
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
}

// MARK: - Lock Screen View
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<ReadingTimerAttributes>
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // 왼쪽: 시간 표시
            HStack(spacing: 0) {
                if context.state.isRunning, let startDate = context.state.timerStartDate {
                    if context.state.isTimerMode, let endDate = context.state.timerEndDate {
                        // 카운트다운 타이머
                        let remaining = endDate.timeIntervalSince(Date())
                        Group {
                            if remaining > 0 {
                                // 진행 중 - 실시간 카운트다운
                                Text(endDate, style: .timer)
                                    .foregroundColor(shouldShowWarning(context.state) ? .red : .white)
                            } else {
                                // 완료 - 고정 텍스트
                                Text("0:00")
                                    .foregroundColor(.red)
                            }
                        }
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    } else {
                        // 경과 시간 (스톱워치)
                        Text(startDate, style: .timer)
                            .font(.system(size: 32, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                } else {
                    // 일시정지 상태
                    Text(formatPausedTime(context.state.pausedTime))
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 오른쪽: 책 아이콘과 제목
            HStack(spacing: 6) {
                Image(systemName: "book.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                
                Text(context.attributes.bookTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 100, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
