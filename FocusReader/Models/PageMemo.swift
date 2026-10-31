import Foundation
import SwiftData

@Model
final class PageMemo {
    var id: UUID = UUID()
    var startPage: Int = 0
    var endPage: Int = 0
    var memo: String = ""
    var imageData: Data? // ⭐️ 사진 저장을 위한 속성 추가
    var createdAt: Date = Date()
    var lastUpdated: Date = Date()
    
    @Relationship(inverse: \Book.memos) var book: Book?
    
    // 🔥 Book 파라미터에 기본값을 주어 유연한 초기화 지원 (imageData 추가)
    init(startPage: Int, endPage: Int, memo: String, book: Book? = nil, imageData: Data? = nil) {
        self.id = UUID()
        self.startPage = startPage
        self.endPage = endPage
        self.memo = memo
        self.imageData = imageData
        self.createdAt = Date()
        self.lastUpdated = Date()
        self.book = book
    }
    
    // ⭐️ 텍스트와 이미지를 함께 업데이트하도록 수정
    func updateMemo(_ newMemo: String, imageData: Data? = nil) {
        self.memo = newMemo
        self.imageData = imageData
        self.lastUpdated = Date()
    }
    
    func updatePageRange(startPage: Int, endPage: Int) {
        self.startPage = startPage
        self.endPage = endPage
        self.lastUpdated = Date()
    }
    
    // ⭐️ 옵셔널 업데이트 메서드에도 imageData 지원
    func update(startPage: Int? = nil, endPage: Int? = nil, memo: String? = nil, imageData: Data? = nil) {
        if let startPage = startPage { self.startPage = startPage }
        if let endPage = endPage { self.endPage = endPage }
        if let memo = memo { self.memo = memo }
        self.imageData = imageData
        self.lastUpdated = Date()
    }
}
