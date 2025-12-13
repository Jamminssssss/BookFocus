import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

@main
struct FocusReaderWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadingTimerLiveActivity()
    }
}

struct ReadingTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingTimerAttributes.self) { context in
            // 잠금 화면 UI
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.25))
                .activitySystemActionForegroundColor(Color.white)
            
        } dynamicIsland: { context in
            DynamicIsland {
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
                
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formatTime(context.state))
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.semibold)
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isTimerMode {
                        ProgressView(value: context.state.elapsedTime,
                                   total: TimeInterval(context.state.targetMinutes * 60))
                            .tint(.blue)
                    }
                }
            } compactLeading: {
                Image(systemName: "book.fill")
                    .foregroundColor(.blue)
            } compactTrailing: {
                Text(formatTimeCompact(context.state))
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.semibold)
            } minimal: {
                Image(systemName: context.state.isRunning ? "timer" : "pause.circle.fill")
                    .foregroundColor(.blue)
            }
        }
    }
    
    private func formatTime(_ state: ReadingTimerAttributes.ContentState) -> String {
        let time = state.isTimerMode ?
            max(0, TimeInterval(state.targetMinutes * 60) - state.elapsedTime) :
            state.elapsedTime
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func formatTimeCompact(_ state: ReadingTimerAttributes.ContentState) -> String {
        let time = state.isTimerMode ?
            max(0, TimeInterval(state.targetMinutes * 60) - state.elapsedTime) :
            state.elapsedTime
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// 잠금 화면 UI - 간단하게
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<ReadingTimerAttributes>
    
    var body: some View {
        VStack(spacing: 16) {
            // 책 이미지
            if let imagePath = context.attributes.bookImagePath,
               let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let imageURL = documentsDirectory.appendingPathComponent(imagePath)
                if let imageData = try? Data(contentsOf: imageURL),
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 120)
                        .cornerRadius(8)
                }
            } else {
                Image(systemName: "book.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
            }
            
            // 책 이름
            Text(context.attributes.bookTitle)
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            // 시간 표시
            Text(formatTime(context.state))
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundColor(shouldShowWarning(context.state) ? .red : .white)
        }
        .padding(20)
    }
    
    private func formatTime(_ state: ReadingTimerAttributes.ContentState) -> String {
        let time = state.isTimerMode ?
            max(0, TimeInterval(state.targetMinutes * 60) - state.elapsedTime) :
            state.elapsedTime
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func shouldShowWarning(_ state: ReadingTimerAttributes.ContentState) -> Bool {
        if state.isTimerMode {
            let remaining = TimeInterval(state.targetMinutes * 60) - state.elapsedTime
            return remaining < 60 && remaining > 0
        }
        return false
    }
}
