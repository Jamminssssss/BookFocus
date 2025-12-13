import ActivityKit
import Foundation

struct ReadingTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var elapsedTime: TimeInterval
        var isRunning: Bool
        var isTimerMode: Bool
        var targetMinutes: Int
    }
    
    var bookTitle: String
    var bookImagePath: String?
    var startTime: Date
}
