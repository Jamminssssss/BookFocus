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
    
    @Relationship(deleteRule: .cascade) var sessions: [ReadingSession]?
    @Relationship(deleteRule: .cascade) var memos: [PageMemo]?
    
    init(title: String, author: String, totalPages: Int, coverImageData: Data? = nil) {
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
        self.sessions = []
        self.memos = []
    }
    
    // 누적 읽기 시간 계산 (세션들의 합계)
    // 🔥 개선: nil 체크 강화 및 명확한 로직
    func updateTotalReadingTime() {
        // sessions가 nil이거나 비어있으면 0으로 설정
        guard let sessions = sessions, !sessions.isEmpty else {
            self.totalReadingTime = 0
            self.lastUpdated = Date()
            return
        }
        
        // 실제 저장된 세션들의 duration 합계 계산
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
        self.currentPage = min(max(0, page), self.totalPages)  // 🔥 범위 검증 추가
        self.lastUpdated = Date()
        checkCompletion()
    }
    
    // 책 정보 업데이트
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
    
    // 🔥 추가: 세션 추가 헬퍼 메서드 (안전한 세션 추가)
    func addSession(_ session: ReadingSession) {
        if sessions == nil {
            sessions = []
        }
        session.book = self
        sessions?.append(session)
        updateTotalReadingTime()
    }
    
    // 🔥 추가: 세션 제거 헬퍼 메서드
    func removeSession(_ session: ReadingSession) {
        sessions?.removeAll { $0.id == session.id }
        updateTotalReadingTime()
    }
}

// 편의 확장
extension Book {
    // 🔥 개선: 실시간 계산된 총 읽기 시간 (저장된 값과 비교 가능)
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
    
    // 🔥 추가: 진행률 계산
    var progressPercentage: Double {
        guard totalPages > 0 else { return 0 }
        return Double(currentPage) / Double(totalPages) * 100
    }
    
    // 🔥 추가: 평균 읽기 속도 (페이지/시간)
    var averageReadingSpeed: Double {
        guard calculatedTotalReadingTime > 0 else { return 0 }
        let totalHours = calculatedTotalReadingTime / 3600
        return Double(currentPage) / totalHours
    }
}
