//
//  Book.swift
//  FocusReader
//
//  Created by JeaminPark on 12/10/25.
//

import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var totalPages: Int = 0
    var currentPage: Int = 0
    var coverImageData: Data?
    var isCompleted: Bool = false
    var totalReadingTime: TimeInterval = 0
    var createdAt: Date = Date()
    var lastUpdated: Date = Date()
    var sessions: [ReadingSession]? = []
    
    var memos: [PageMemo]? = []  // 🔥 Changed from [Memo] to [PageMemo]
    
    // 대출/반납 날짜
    var checkoutDate: Date? = nil
    var dueDate: Date? = nil
    
    init(title: String, author: String, totalPages: Int, coverImageData: Data? = nil, checkoutDate: Date? = nil, dueDate: Date? = nil) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.totalPages = totalPages
        self.currentPage = 0
        self.coverImageData = coverImageData
        self.isCompleted = false
        self.totalReadingTime = 0
        self.createdAt = Date()
        self.lastUpdated = Date()
        self.checkoutDate = checkoutDate
        self.dueDate = dueDate
    }
    
    // 누적 읽기 시간 계산 (세션들의 합계)
    func updateTotalReadingTime() {
        guard let sessions = sessions, !sessions.isEmpty else {
            self.totalReadingTime = 0
            self.lastUpdated = Date()
            return
        }
        
        self.totalReadingTime = sessions.reduce(0) { $0 + $1.duration }
        self.lastUpdated = Date()
    }
    
    // 완독 체크 (현재 페이지가 총 페이지 이상인지)
    func checkCompletion() {
        self.isCompleted = self.currentPage >= self.totalPages
        self.lastUpdated = Date()
    }
    
    // 페이지 업데이트
    func updateCurrentPage(_ page: Int) {
        self.currentPage = min(max(0, page), self.totalPages)
        self.lastUpdated = Date()
        checkCompletion()
    }
    
    // 책 정보 업데이트
    func updateInfo(title: String? = nil, author: String? = nil, totalPages: Int? = nil, coverImageData: Data? = nil, checkoutDate: Date? = nil, dueDate: Date? = nil) {
        if let title = title {
            self.title = title
        }
        if let author = author {
            self.author = author
        }
        if let totalPages = totalPages {
            self.totalPages = totalPages
        }
        if let coverImageData = coverImageData {
            self.coverImageData = coverImageData
        }
        if let checkoutDate = checkoutDate {
            self.checkoutDate = checkoutDate
        }
        if let dueDate = dueDate {
            self.dueDate = dueDate
        }
        self.lastUpdated = Date()
        checkCompletion()
    }
    
    // 세션 추가 헬퍼 메서드
    func addSession(_ session: ReadingSession) {
        if sessions == nil {
            sessions = []
        }
        session.book = self
        sessions?.append(session)
        updateTotalReadingTime()
    }
    
    // 세션 제거 헬퍼 메서드
    func removeSession(_ session: ReadingSession) {
        sessions?.removeAll { $0.id == session.id }
        updateTotalReadingTime()
    }
    
    // 🔥 Added: 메모 추가 헬퍼 메서드
    func addMemo(_ memo: PageMemo) {
        if memos == nil {
            memos = []
        }
        memo.book = self
        memos?.append(memo)
        self.lastUpdated = Date()
    }
    
    // 🔥 Added: 메모 제거 헬퍼 메서드
    func removeMemo(_ memo: PageMemo) {
        memos?.removeAll { $0.id == memo.id }
        self.lastUpdated = Date()
    }
}

// 편의 확장
extension Book {
    var calculatedTotalReadingTime: TimeInterval {
        return sessions?.reduce(0) { $0 + $1.duration } ?? 0
    }
    
    var sessionCount: Int {
        return sessions?.count ?? 0
    }
    
    var memoCount: Int {
        return memos?.count ?? 0
    }
    
    var formattedReadingTime: String {
        let totalSeconds = calculatedTotalReadingTime
        let hours = Int(totalSeconds / 3600)
        let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var progressPercentage: Double {
        guard totalPages > 0 else { return 0 }
        return Double(currentPage) / Double(totalPages) * 100
    }
    
    var averageReadingSpeed: Double {
        guard calculatedTotalReadingTime > 0 else { return 0 }
        let totalHours = calculatedTotalReadingTime / 3600
        return Double(currentPage) / totalHours
    }
    
    // MARK: - Due date helpers
    var hasDueDate: Bool {
        return dueDate != nil
    }

    func nineAMLocal(on date: Date) -> Date {
        var cal = Calendar.current
        cal.timeZone = .current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        var nine = DateComponents()
        nine.year = comps.year
        nine.month = comps.month
        nine.day = comps.day
        nine.hour = 9
        nine.minute = 0
        nine.second = 0
        return cal.date(from: nine) ?? date
    }

    var dueMinus1DayAtNine: Date? {
        guard let due = dueDate else { return nil }
        let d = Calendar.current.date(byAdding: .day, value: -1, to: due) ?? due
        return nineAMLocal(on: d)
    }

    var dueDayAtNine: Date? {
        guard let due = dueDate else { return nil }
        return nineAMLocal(on: due)
    }

    struct DueReminderPayload: Codable, Equatable {
        let id: String
        let title: String
        let dueMinus1DayAtNine: Date?
        let dueDayAtNine: Date?
    }

    var dueReminderPayload: DueReminderPayload? {
        guard let _ = dueDate else { return nil }
        return DueReminderPayload(
            id: id.uuidString,
            title: title,
            dueMinus1DayAtNine: dueMinus1DayAtNine,
            dueDayAtNine: dueDayAtNine
        )
    }
}
