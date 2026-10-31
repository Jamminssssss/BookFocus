import Foundation
import SwiftData

// ⭐️ 포맷 구분을 위한 열거형
enum BookFormat: String, Codable {
    case physical = "physical"
    case ebook = "ebook"
}

// ⭐️ 도서관 대출 상태 구분을 위한 열거형
public enum LoanStatus: String, Codable, CaseIterable {
    case none = "none"
    case borrowed = "borrowed"
    case returned = "returned"
    case renewed = "renewed"
}

@Model
final class Book {
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var totalPages: Int = 0
    var currentPage: Int = 0
    var formatRawValue: String = BookFormat.physical.rawValue
    var loanStatusRawValue: String = LoanStatus.none.rawValue // ⭐️ 추가: 대출 상태
    var coverImageData: Data?
    var isCompleted: Bool = false
    var totalReadingTime: TimeInterval = 0
    var createdAt: Date = Date()
    var lastUpdated: Date = Date()
    
    // 🔥 책 삭제 시 하위 세션/메모도 함께 삭제
    @Relationship(deleteRule: .cascade) var sessions: [ReadingSession]? = []
    @Relationship(deleteRule: .cascade) var memos: [PageMemo]? = []
    
    var checkoutDate: Date? = nil
    var dueDate: Date? = nil
    
    // 연산 프로퍼티로 쉽게 포맷 접근
    var format: BookFormat {
        get { BookFormat(rawValue: formatRawValue) ?? .physical }
        set { formatRawValue = newValue.rawValue }
    }
    
    var isEbook: Bool { format == .ebook }
    
    // ⭐️ 연산 프로퍼티로 쉽게 대출 상태 접근
    var loanStatus: LoanStatus {
        get { LoanStatus(rawValue: loanStatusRawValue) ?? .none }
        set { loanStatusRawValue = newValue.rawValue }
    }
    
    init(title: String, author: String, totalPages: Int, format: BookFormat = .physical, coverImageData: Data? = nil, checkoutDate: Date? = nil, dueDate: Date? = nil) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.formatRawValue = format.rawValue
        self.loanStatusRawValue = (checkoutDate != nil || dueDate != nil) ? LoanStatus.borrowed.rawValue : LoanStatus.none.rawValue
        self.totalPages = format == .ebook ? 100 : totalPages // ⭐️ 전자책이면 100%로 고정
        self.currentPage = 0
        self.coverImageData = coverImageData
        self.isCompleted = false
        self.totalReadingTime = 0
        self.createdAt = Date()
        self.lastUpdated = Date()
        self.checkoutDate = checkoutDate
        self.dueDate = dueDate
    }
    
    func updateTotalReadingTime() {
        guard let sessions = sessions, !sessions.isEmpty else {
            self.totalReadingTime = 0
            self.lastUpdated = Date()
            return
        }
        self.totalReadingTime = sessions.reduce(0) { $0 + $1.duration }
        self.lastUpdated = Date()
    }
    
    func checkCompletion() {
        self.isCompleted = self.currentPage >= self.totalPages
        self.lastUpdated = Date()
    }
    
    func updateCurrentPage(_ page: Int) {
        self.currentPage = min(max(0, page), self.totalPages)
        self.lastUpdated = Date()
        checkCompletion()
    }

    /// Records a bookmark without manufacturing a reading session or duration.
    /// Earlier positions are allowed so an accidental entry can be corrected.
    func saveReadingProgress(_ page: Int, in context: ModelContext) throws {
        guard page >= 0, page <= totalPages else { throw ProgressError.invalidPage }
        let previousPage = currentPage
        let previousCompletion = isCompleted
        let previousUpdate = lastUpdated
        updateCurrentPage(page)
        do {
            try context.save()
        } catch {
            currentPage = previousPage
            isCompleted = previousCompletion
            lastUpdated = previousUpdate
            throw error
        }
    }

    enum ProgressError: Error {
        case invalidPage
    }
    
    func updateInfo(title: String? = nil, author: String? = nil, totalPages: Int? = nil, format: BookFormat? = nil, coverImageData: Data? = nil, checkoutDate: Date? = nil, dueDate: Date? = nil) {
        if let title = title { self.title = title }
        if let author = author { self.author = author }
        if let format = format {
            self.format = format
            if format == .ebook { self.totalPages = 100 }
        }
        if let totalPages = totalPages, !self.isEbook { self.totalPages = totalPages }
        if let coverImageData = coverImageData { self.coverImageData = coverImageData }
        if let checkoutDate = checkoutDate { self.checkoutDate = checkoutDate }
        if let dueDate = dueDate { self.dueDate = dueDate }
        
        self.lastUpdated = Date()
        checkCompletion()
    }
    
    func addSession(_ session: ReadingSession) {
        if sessions == nil { sessions = [] }
        session.book = self
        sessions?.append(session)
        updateTotalReadingTime()
    }
    
    func removeSession(_ session: ReadingSession) {
        sessions?.removeAll { $0.id == session.id }
        updateTotalReadingTime()
    }
    
    func addMemo(_ memo: PageMemo) {
        if memos == nil { memos = [] }
        memo.book = self
        memos?.append(memo)
        self.lastUpdated = Date()
    }
    
    func removeMemo(_ memo: PageMemo) {
        memos?.removeAll { $0.id == memo.id }
        self.lastUpdated = Date()
    }
}

extension Book {
    var calculatedTotalReadingTime: TimeInterval {
        return sessions?.reduce(0) { $0 + $1.duration } ?? 0
    }
    
    var sessionCount: Int { return sessions?.count ?? 0 }
    var memoCount: Int { return memos?.count ?? 0 }
    
    var formattedReadingTime: String {
        let totalSeconds = calculatedTotalReadingTime
        let hours = Int(totalSeconds / 3600)
        let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
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
    
    var hasDueDate: Bool { return dueDate != nil }

    func nineAMLocal(on date: Date) -> Date {
        var cal = Calendar.current; cal.timeZone = .current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        var nine = DateComponents()
        nine.year = comps.year; nine.month = comps.month; nine.day = comps.day; nine.hour = 9; nine.minute = 0; nine.second = 0
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
        guard dueDate != nil else { return nil }
        return DueReminderPayload(id: id.uuidString, title: title, dueMinus1DayAtNine: dueMinus1DayAtNine, dueDayAtNine: dueDayAtNine)
    }
}
