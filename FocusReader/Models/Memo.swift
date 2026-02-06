//
//  Memo.swift
//  FocusReader
//
//  Created by Assistant on 1/29/26.
//

import Foundation
import SwiftData

@Model
final class Memo {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var lastUpdated: Date = Date()

    // Optional inverse relationship to Book; SwiftData can infer if Book has [Memo] collection
    var book: Book?

    init(text: String, book: Book? = nil) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.lastUpdated = Date()
        self.book = book
    }

    func updateText(_ newText: String) {
        self.text = newText
        self.lastUpdated = Date()
    }
}
