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
    var coverImageData: Data?  // 🔥 imagePath → coverImageData로 변경
    var isCompleted: Bool = false
    var totalReadingTime: TimeInterval = 0
    var createdAt: Date = Date()
    var lastUpdated: Date = Date()
    
    @Relationship(deleteRule: .cascade) var sessions: [ReadingSession]?
    @Relationship(deleteRule: .cascade) var memos: [PageMemo]?
    
    init(title: String, author: String, totalPages: Int, coverImageData: Data? = nil) {  // 🔥 파라미터 변경
        self.id = UUID()
        self.title = title
        self.author = author
        self.totalPages = totalPages
        self.currentPage = 0
        self.coverImageData = coverImageData  // 🔥 변경
        self.isCompleted = false
        self.totalReadingTime = 0
        self.createdAt = Date()
        self.lastUpdated = Date()
        self.sessions = []
        self.memos = []
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
        self.currentPage = page
        self.lastUpdated = Date()
        checkCompletion()
    }
    
    // 🔥 책 정보 업데이트 (이미지 파라미터 추가)
    func updateInfo(title: String? = nil, author: String? = nil, totalPages: Int? = nil, coverImageData: Data? = nil) {
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
        self.lastUpdated = Date()
        checkCompletion()
    }
}

// 🔥 편의 확장 (선택사항 - 있으면 편리)
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
}
