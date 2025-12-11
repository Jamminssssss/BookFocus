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
    var id: UUID
    var startPage: Int
    var endPage: Int
    var memo: String
    var createdAt: Date
    @Relationship(inverse: \Book.memos) var book: Book?
    
    init(startPage: Int, endPage: Int, memo: String, book: Book) {
        self.id = UUID()
        self.startPage = startPage
        self.endPage = endPage
        self.memo = memo
        self.createdAt = Date()
        self.book = book
    }
}
