import Foundation
import SwiftData

// Run with swiftc and the Book, ReadingSession and PageMemo model source files.
@MainActor
func checkReadingProgress() throws {
    let schema = Schema([Book.self, ReadingSession.self, PageMemo.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    let book = Book(title: "A bookmark", author: "Reader", totalPages: 200)
    context.insert(book)

    try book.saveReadingProgress(42, in: context)
    precondition(book.currentPage == 42 && !book.isCompleted)
    precondition(book.sessions?.isEmpty == true && book.totalReadingTime == 0)
    let savedSessions = try context.fetch(FetchDescriptor<ReadingSession>())
    precondition(savedSessions.isEmpty)

    // Check the saved value through a different context, as when reopening the book.
    let reloadedContext = ModelContext(container)
    let reloadedBooks = try reloadedContext.fetch(FetchDescriptor<Book>())
    precondition(reloadedBooks.first?.currentPage == 42)

    let session = ReadingSession(startTime: Date().addingTimeInterval(-600), startPage: 0)
    session.finalize(endPage: 20, measuredDuration: 600)
    context.insert(session)
    book.addSession(session)
    let originalSessionID = session.id
    let originalEndTime = session.endTime

    try book.saveReadingProgress(200, in: context)
    precondition(book.isCompleted)
    try book.saveReadingProgress(30, in: context)
    precondition(book.currentPage == 30 && !book.isCompleted)
    precondition(book.sessions?.count == 1 && book.sessions?.first?.id == originalSessionID)
    precondition(book.totalReadingTime == 600 && session.duration == 600)
    precondition(session.startPage == 0 && session.endPage == 20 && session.endTime == originalEndTime)

    let previousUpdate = book.lastUpdated
    for invalidPage in [-1, 201, Int.max] {
        do {
            try book.saveReadingProgress(invalidPage, in: context)
            preconditionFailure("Out-of-range page was saved")
        } catch Book.ProgressError.invalidPage {
            precondition(book.currentPage == 30 && book.lastUpdated == previousUpdate)
        }
    }
    try book.saveReadingProgress(0, in: context)
    precondition(book.currentPage == 0 && !book.isCompleted)

    let ebook = Book(title: "An ebook", author: "Reader", totalPages: 900, format: .ebook)
    context.insert(ebook)
    try ebook.saveReadingProgress(65, in: context)
    precondition(ebook.currentPage == 65 && ebook.totalPages == 100 && !ebook.isCompleted)
    try ebook.saveReadingProgress(100, in: context)
    precondition(ebook.isCompleted && ebook.totalReadingTime == 0 && ebook.sessions?.isEmpty == true)
    print("Reading progress checks passed")
}

try checkReadingProgress()
