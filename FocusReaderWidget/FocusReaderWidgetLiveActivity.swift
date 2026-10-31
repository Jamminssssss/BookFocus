import ActivityKit
import WidgetKit
import SwiftUI

struct FocusReaderWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingTimerAttributes.self) { context in
            // MARK: - 잠금화면 (Lock Screen) 아날로그 UI
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.clear)
                .activitySystemActionForegroundColor(Color.primary)
            
        } dynamicIsland: { context in
            // MARK: - 다이내믹 아일랜드 (Dynamic Island) 아날로그 UI
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("reading.", systemImage: "book")
                        .font(.custom("ChalkboardSE-Regular", size: 14))
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // ⭐️ [수정]: 클로저 내 let 변수 선언을 제거하고 익스텐션 속성을 직접 호출하여 제네릭 추론 에러 해결
                    Text(context.state.isEbook ? "\((Double(context.state.currentPage) / 100).formatted(.percent.precision(.fractionLength(0))))" : "\(context.state.currentPage) p")
                        .font(.custom("ChalkboardSE-Regular", size: 14))
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.bookTitle)
                            .font(.custom("ChalkboardSE-Bold", size: 16))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        WidgetTimerView(context: context, fontSize: 20, color: .white)
                    }
                }
            } compactLeading: {
                Image(systemName: "book")
                    .foregroundColor(.white)
            } compactTrailing: {
                CompactWidgetTimerView(context: context)
            } minimal: {
                Image(systemName: "book")
                    .foregroundColor(.white)
            }
            .keylineTint(Color.white)
        }
    }
}

// MARK: - 잠금화면용 아날로그 스케치 뷰
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<ReadingTimerAttributes>
    @Environment(\.colorScheme) private var colorScheme
    
    var paperColor: Color { colorScheme == .dark ? Color.black : Color(red: 0.98, green: 0.97, blue: 0.95) }
    var inkColor: Color { colorScheme == .dark ? Color.white : Color.black }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "book")
                    .foregroundColor(inkColor)
                Text(context.attributes.bookTitle)
                    .font(.custom("ChalkboardSE-Bold", size: 16))
                    .lineLimit(1)
                    .foregroundColor(inkColor)
                Spacer()
                
                // ⭐️ [수정]: 익스텐션 속성 직접 호출
                if context.state.isEbook {
                    Text("\((Double(context.state.currentPage) / 100).formatted(.percent.precision(.fractionLength(0)))) / \(1.0.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.custom("ChalkboardSE-Regular", size: 14))
                        .foregroundColor(inkColor.opacity(0.7))
                } else {
                    Text("\(context.state.currentPage) / \(context.state.totalPages) p")
                        .font(.custom("ChalkboardSE-Regular", size: 14))
                        .foregroundColor(inkColor.opacity(0.7))
                }
            }
            
            HStack {
                WidgetTimerView(context: context, fontSize: 32, color: inkColor)
                Spacer()
                Image(systemName: context.state.isRunning ? "pencil" : "pause")
                    .font(.title2)
                    .foregroundColor(inkColor)
            }
        }
        .padding()
        .background(paperColor)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(inkColor, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 타이머 뷰 빌더
struct WidgetTimerView: View {
    let context: ActivityViewContext<ReadingTimerAttributes>
    let fontSize: CGFloat
    let color: Color
    
    var body: some View {
        if context.state.isRunning {
            if let startDate = context.state.timerStartDate {
                let adjustedStartDate = startDate.addingTimeInterval(-context.state.pausedTime)
                
                if context.state.isTimerMode, let endDate = context.state.timerEndDate {
                    let safeEndDate = max(adjustedStartDate.addingTimeInterval(1), endDate)
                    Text(timerInterval: adjustedStartDate...safeEndDate, countsDown: true)
                        .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(endDate.timeIntervalSinceNow < 60 ? .red : color)
                        .minimumScaleFactor(0.5)
                } else {
                    Text(timerInterval: adjustedStartDate...Date.distantFuture, countsDown: false)
                        .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(color)
                        .minimumScaleFactor(0.5)
                }
            }
        } else {
            Text(formatTime(context.state.pausedTime))
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(color)
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let h = Int(time) / 3600; let m = Int(time) / 60 % 60; let s = Int(time) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - 다이내믹 아일랜드 우측 컴팩트 타이머 뷰
struct CompactWidgetTimerView: View {
    let context: ActivityViewContext<ReadingTimerAttributes>
    
    var body: some View {
        if context.state.isRunning {
            if let startDate = context.state.timerStartDate {
                let adjustedStartDate = startDate.addingTimeInterval(-context.state.pausedTime)
                
                if context.state.isTimerMode, let endDate = context.state.timerEndDate {
                    let safeEndDate = max(adjustedStartDate.addingTimeInterval(1), endDate)
                    Text(timerInterval: adjustedStartDate...safeEndDate, countsDown: true)
                        .frame(minWidth: 40)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                } else {
                    Text(timerInterval: adjustedStartDate...Date.distantFuture, countsDown: false)
                        .frame(minWidth: 40)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                }
            }
        } else {
            Image(systemName: "pause").foregroundColor(.white)
        }
    }
}

// 🔥 [에러 해결을 위한 핵심 익스텐션]: ReadingTimerAttributes.ContentState에 isEbook 속성 추가
extension ReadingTimerAttributes.ContentState {
    var isEbook: Bool { format == "ebook" || (format == nil && totalPages == 100) }
}
