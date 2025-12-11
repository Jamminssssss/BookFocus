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
    var id: UUID
    var title: String
    var author: String
    var totalPages: Int
    var currentPage: Int
    var imagePath: String?
    var isCompleted: Bool
    var totalReadingTime: TimeInterval // 누적 읽기 시간 (초)
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var sessions: [ReadingSession]?
    @Relationship(deleteRule: .cascade) var memos: [PageMemo]?
    
    init(title: String, author: String, totalPages: Int, imagePath: String? = nil) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.totalPages = totalPages
        self.currentPage = 0
        self.imagePath = imagePath
        self.isCompleted = false
        self.totalReadingTime = 0
        self.createdAt = Date()
        self.sessions = []
        self.memos = []
    }
    
    // 누적 읽기 시간 계산 (세션들의 합계)
    func updateTotalReadingTime() {
        guard let sessions = sessions, !sessions.isEmpty else {
            self.totalReadingTime = 0
            return
        }
        self.totalReadingTime = sessions.reduce(0) { $0 + $1.duration }
    }
    
    // 완독 체크 (현재 페이지가 총 페이지 이상인지)
    func checkCompletion() {
        self.isCompleted = self.currentPage >= self.totalPages
    }
}
