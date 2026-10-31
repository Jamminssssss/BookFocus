import Foundation
import ActivityKit

class LiveActivityManager {
    static let shared = LiveActivityManager()
    
    private var currentActivity: Activity<ReadingTimerAttributes>?
    
    private init() {}
    
    // 1. 라이브 액티비티 시작
    func startActivity(
        bookTitle: String,
        isTimerMode: Bool,
        targetMinutes: Int,
        currentPage: Int,
        totalPages: Int
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let sessionStart = Date()
        let attributes = ReadingTimerAttributes(
            bookTitle: bookTitle,
            sessionStartTime: sessionStart
        )
        
        // 목표 타이머 모드일 경우 종료 시간 계산
        var endDate: Date? = nil
        if isTimerMode {
            endDate = sessionStart.addingTimeInterval(TimeInterval(targetMinutes * 60))
        }
        
        let contentState = ReadingTimerAttributes.ContentState(
            timerStartDate: sessionStart,
            pausedTime: 0,
            isRunning: true,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes,
            timerEndDate: endDate,
            currentPage: currentPage,
            totalPages: totalPages
        )
        
        endActivity() // 기존에 켜져 있다면 방어 차원에서 강제 종료
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil)
            )
        } catch {
            print("라이브 액티비티 시작 실패: \(error.localizedDescription)")
        }
    }
    
    // 2. 라이브 액티비티 업데이트 (일시정지, 재개, 페이지 변경 등)
    func updateActivity(
        isRunning: Bool,
        timerStartDate: Date?,
        pausedTime: TimeInterval,
        isTimerMode: Bool,
        targetMinutes: Int,
        timerEndDate: Date?,
        currentPage: Int,
        totalPages: Int
    ) {
        guard let activity = currentActivity else { return }
        
        let contentState = ReadingTimerAttributes.ContentState(
            timerStartDate: timerStartDate,
            pausedTime: pausedTime,
            isRunning: isRunning,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes,
            timerEndDate: timerEndDate,
            currentPage: currentPage,
            totalPages: totalPages
        )
        
        Task {
            await activity.update(
                ActivityContent(state: contentState, staleDate: nil)
            )
        }
    }
    
    // 3. 라이브 액티비티 종료
    func endActivity() {
        Task {
            for activity in Activity<ReadingTimerAttributes>.activities {
                let finalState = activity.content.state
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .immediate // 즉시 화면에서 제거
                )
            }
            self.currentActivity = nil
        }
    }
}
