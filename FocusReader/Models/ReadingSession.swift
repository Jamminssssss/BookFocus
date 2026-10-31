import Foundation
import SwiftData

@Model
final class ReadingSession {
    var id: UUID = UUID()
    var startTime: Date = Date()
    var endTime: Date?
    var startPage: Int = 0
    var endPage: Int?
    var duration: TimeInterval = 0
    var lastUpdated: Date = Date()
    
    @Relationship(inverse: \Book.sessions) var book: Book?
    
    // 🔥 [수정] convenience init 제거. Book을 Optional로 받아 단일 초기화로 처리
    init(id: UUID = UUID(), startTime: Date, startPage: Int, book: Book? = nil) {
        self.id = id
        self.startTime = startTime
        self.startPage = startPage
        self.endTime = nil
        self.endPage = nil
        self.duration = 0
        self.lastUpdated = Date()
        self.book = book
    }
    
    func endSession(endPage: Int) {
        self.endTime = Date()
        self.endPage = endPage
        
        if let endTime = self.endTime {
            self.duration = endTime.timeIntervalSince(self.startTime)
        }
        
        self.lastUpdated = Date()
        book?.updateTotalReadingTime()
    }

    /// Finalizes page metadata without recalculating a duration already measured by
    /// the pause-aware timer.
    func finalize(endPage: Int, measuredDuration: TimeInterval) {
        self.endTime = Date()
        self.endPage = endPage
        self.duration = max(0, measuredDuration)
        self.lastUpdated = Date()
        book?.updateTotalReadingTime()
    }
    
    func updateDuration() {
        if endTime == nil {
            self.duration = Date().timeIntervalSince(self.startTime)
            self.lastUpdated = Date()
        }
    }
    
    func adjustDuration(_ newDuration: TimeInterval) {
        self.duration = newDuration
        self.lastUpdated = Date()
        book?.updateTotalReadingTime()
    }
    
    func update(startPage: Int? = nil, endPage: Int? = nil, startTime: Date? = nil, endTime: Date? = nil) {
        if let startPage = startPage { self.startPage = startPage }
        if let endPage = endPage { self.endPage = endPage }
        if let startTime = startTime { self.startTime = startTime }
        if let endTime = endTime { self.endTime = endTime }
        
        if let end = self.endTime {
            self.duration = end.timeIntervalSince(self.startTime)
        }
        
        self.lastUpdated = Date()
        book?.updateTotalReadingTime()
    }
}
