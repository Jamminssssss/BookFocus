//
//  ReadingSession.swift
//  FocusReader
//
//  Created by JeaminPark on 12/10/25.
//

import Foundation
import SwiftData

@Model
final class ReadingSession {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var startPage: Int
    var endPage: Int?
    var duration: TimeInterval // 읽은 시간 (초)
    @Relationship(inverse: \Book.sessions) var book: Book?
    
    init(startTime: Date, startPage: Int, book: Book) {
        self.id = UUID()
        self.startTime = startTime
        self.startPage = startPage
        self.endTime = nil
        self.endPage = nil
        self.duration = 0
        self.book = book
    }
    
    // 세션 종료 및 시간 계산
    func endSession(endPage: Int) {
        self.endTime = Date()
        self.endPage = endPage
        
        if let endTime = self.endTime {
            self.duration = endTime.timeIntervalSince(self.startTime)
        }
    }
}

