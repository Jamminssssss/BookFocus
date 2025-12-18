//
//  PageMemo.swift
//  FocusReader
//
//  Created by JeaminPark on 12/10/25.
//

import Foundation
import SwiftData

@Model
final class PageMemo {
    var id: UUID = UUID()  // 🔥 기본값 추가
    var startPage: Int = 0  // 🔥 기본값 추가
    var endPage: Int = 0  // 🔥 기본값 추가
    var memo: String = ""  // 🔥 기본값 추가
    var createdAt: Date = Date()  // 🔥 기본값 추가
    var lastUpdated: Date = Date()  // 🔥 기본값 추가
    
    @Relationship(inverse: \Book.memos) var book: Book?
    
    init(startPage: Int, endPage: Int, memo: String, book: Book) {
        self.id = UUID()
        self.startPage = startPage
        self.endPage = endPage
        self.memo = memo
        self.createdAt = Date()
        self.lastUpdated = Date()
        self.book = book
    }
    
    // 🔥 메모 수정
    func updateMemo(_ newMemo: String) {
        self.memo = newMemo
        self.lastUpdated = Date()
    }
    
    // 🔥 페이지 범위 수정
    func updatePageRange(startPage: Int, endPage: Int) {
        self.startPage = startPage
        self.endPage = endPage
        self.lastUpdated = Date()
    }
    
    // 🔥 전체 수정
    func update(startPage: Int? = nil, endPage: Int? = nil, memo: String? = nil) {
        if let startPage = startPage {
            self.startPage = startPage
        }
        if let endPage = endPage {
            self.endPage = endPage
        }
        if let memo = memo {
            self.memo = memo
        }
        self.lastUpdated = Date()
    }
}
