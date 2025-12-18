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
    var id: UUID = UUID()  // 🔥 기본값 추가
    var startTime: Date = Date()  // 🔥 기본값 추가
    var endTime: Date?  // 이미 옵셔널
    var startPage: Int = 0  // 🔥 기본값 추가
    var endPage: Int?  // 이미 옵셔널
    var duration: TimeInterval = 0  // 🔥 기본값 추가
    var lastUpdated: Date = Date()  // 🔥 기본값 추가
    
    @Relationship(inverse: \Book.sessions) var book: Book?
    
    init(startTime: Date, startPage: Int, book: Book) {
        self.id = UUID()
        self.startTime = startTime
        self.startPage = startPage
        self.endTime = nil
        self.endPage = nil
        self.duration = 0
        self.lastUpdated = Date()
        self.book = book
    }
    
    // 세션 종료 및 시간 계산
    func endSession(endPage: Int) {
        self.endTime = Date()
        self.endPage = endPage
        
        if let endTime = self.endTime {
            self.duration = endTime.timeIntervalSince(self.startTime)
        }
        
        self.lastUpdated = Date()
        
        // 부모 Book의 총 읽기 시간도 업데이트
        book?.updateTotalReadingTime()
    }
    
    // 🔥 진행 중인 세션의 시간 업데이트
    func updateDuration() {
        if endTime == nil {
            self.duration = Date().timeIntervalSince(self.startTime)
            self.lastUpdated = Date()
        }
    }
    
    // 🔥 수동으로 시간 조정
    func adjustDuration(_ newDuration: TimeInterval) {
        self.duration = newDuration
        self.lastUpdated = Date()
        book?.updateTotalReadingTime()
    }
    
    // 🔥 세션 정보 수정
    func update(startPage: Int? = nil, endPage: Int? = nil, startTime: Date? = nil, endTime: Date? = nil) {
        if let startPage = startPage {
            self.startPage = startPage
        }
        if let endPage = endPage {
            self.endPage = endPage
        }
        if let startTime = startTime {
            self.startTime = startTime
        }
        if let endTime = endTime {
            self.endTime = endTime
        }
        
        if let end = self.endTime {
            self.duration = end.timeIntervalSince(self.startTime)
        }
        
        self.lastUpdated = Date()
        book?.updateTotalReadingTime()
    }
}
