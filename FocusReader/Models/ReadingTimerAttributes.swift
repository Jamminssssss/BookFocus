import ActivityKit
import Foundation

struct ReadingTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Date 기반으로 변경 - 시스템이 자동으로 시간 계산
        var timerStartDate: Date?        // 타이머 시작 시간
        var pausedTime: TimeInterval     // 일시정지된 총 시간
        var isRunning: Bool
        var isTimerMode: Bool
        var targetMinutes: Int
        var timerEndDate: Date?          // 타이머 모드일 때 종료 시간
        
        // 🔥 새로 추가
        var currentPage: Int
        var totalPages: Int
    }
    
    var bookTitle: String
    var bookCoverImageData: Data?       // 🔥 imagePath → coverImageData
    var sessionStartTime: Date           // 세션 시작 시간 (변경 없음)
}
