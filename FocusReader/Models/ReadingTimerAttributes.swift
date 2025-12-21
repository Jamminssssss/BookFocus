import ActivityKit
import Foundation

struct ReadingTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var timerStartDate: Date?
        var pausedTime: TimeInterval
        var isRunning: Bool
        var isTimerMode: Bool
        var targetMinutes: Int
        var timerEndDate: Date?
        var currentPage: Int
        var totalPages: Int
    }
    
    var bookTitle: String
    // ❌ 이미지 데이터 제거 (attributesTooLarge 에러 해결)
    var sessionStartTime: Date
}
