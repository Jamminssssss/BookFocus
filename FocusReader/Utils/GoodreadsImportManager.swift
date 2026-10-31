import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class GoodreadsImportManager: ObservableObject {
    @Published var isImporting = false
    @Published var totalBooks = 0
    @Published var processedBooks = 0
    @Published var importedCount = 0
    @Published var duplicateCount = 0
    @Published var failedCount = 0
    @Published var notFoundCount = 0
    
    // AddBookView와 동일하게 API 키를 가져옵니다.
    private let apiKey = GoogleBooksConfiguration.apiKey
    
    // MARK: - Core Import Function
    func importFromCSV(url: URL, context: ModelContext, existingBooks: [Book]) async {
        isImporting = true
        resetCounters()
        
        // iOS 보안 정책: 외부 파일 접근 권한 요청
        guard url.startAccessingSecurityScopedResource() else {
            failedCount += 1
            isImporting = false
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try String(contentsOf: url, encoding: .utf8)
            let parsedRows = parseGoodreadsCSV(data)
            totalBooks = parsedRows.count
            
            // 기존 도서 중복 검사용 Set (제목-저자 기준)
            var existingKeys = Set(existingBooks.map { generateKey(title: $0.title, author: $0.author) })
            
            for row in parsedRows {
                let duplicateKey = generateKey(title: row.title, author: row.author)
                if existingKeys.contains(duplicateKey) {
                    duplicateCount += 1
                    processedBooks += 1
                    continue
                }
                
                await processRow(row, context: context)
                existingKeys.insert(duplicateKey)
                processedBooks += 1
            }
            
            try? context.save()
            
        } catch {
            failedCount += 1
        }
        
        isImporting = false
    }
    
    // MARK: - Process Individual Row
    private func processRow(_ row: GoodreadsRow, context: ModelContext) async {
        var fetchedInfo: (pages: Int, coverData: Data?) = (row.pages, nil)
        var foundInAPI = false
        
        // Google Books API 연동 (AddBookView의 GoogleBooksResponse 모델 재사용)
        if let apiResult = await fetchFromGoogleBooks(isbn: row.isbn, title: row.title, author: row.author) {
            foundInAPI = true
            if let apiPages = apiResult.pageCount, apiPages > 0 {
                fetchedInfo.pages = apiPages
            }
            if let imageURL = apiResult.imageURL {
                fetchedInfo.coverData = await downloadImage(from: imageURL)
            }
        }
        
        if !foundInAPI { notFoundCount += 1 }
        
        let totalPages = max(fetchedInfo.pages, 1)
        var currentPage = 0
        var isCompleted = false
        
        // Goodreads의 독서 상태 반영
        if row.exclusiveShelf == "read" {
            currentPage = totalPages
            isCompleted = true
        }
        
        // 기존 Book 모델 이니셜라이저 사용
        let newBook = Book(
            title: row.title,
            author: row.author,
            totalPages: totalPages,
            format: .physical, // 기본적으로 종이책으로 세팅
            coverImageData: fetchedInfo.coverData,
            checkoutDate: nil,
            dueDate: nil
        )
        newBook.currentPage = currentPage
        newBook.isCompleted = isCompleted
        
        guard let count = try? context.fetchCount(FetchDescriptor<Book>()),
              FreeLimitManager.shared.canAddBook(isPremium: StoreKitManager.shared.isPremium, currentBookCount: count) else {
            failedCount += 1
            return
        }
        context.insert(newBook)
        importedCount += 1
    }
    
    // MARK: - API Integration
    private func fetchFromGoogleBooks(isbn: String, title: String, author: String) async -> (pageCount: Int?, imageURL: URL?)? {
        var query = ""
        if !isbn.isEmpty {
            query = "isbn:\(isbn)"
        } else {
            query = "intitle:\(title)+inauthor:\(author)"
        }
        
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        
        var urlString = "https://www.googleapis.com/books/v1/volumes?q=\(encodedQuery)&maxResults=1"
        if !apiKey.isEmpty { urlString += "&key=\(apiKey)" }
        
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            // AddBookView.swift에 정의된 GoogleBooksResponse를 사용합니다.
            let result = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
            
            guard let bookData = result.items?.first?.volumeInfo else { return nil }
            
            var imageURL: URL? = nil
            if let thumbnail = bookData.imageLinks?.thumbnail {
                imageURL = URL(string: thumbnail.replacingOccurrences(of: "http://", with: "https://"))
            }
            
            return (bookData.pageCount, imageURL)
        } catch {
            return nil
        }
    }
    
    private func downloadImage(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        } catch {
            return nil
        }
    }
    
    private func generateKey(title: String, author: String) -> String {
        return "\(title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))-\(author.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))"
    }
    
    private func resetCounters() {
        totalBooks = 0; processedBooks = 0; importedCount = 0; duplicateCount = 0; failedCount = 0; notFoundCount = 0
    }
}

// MARK: - CSV Parsing Utilities
struct GoodreadsRow {
    var title: String
    var author: String
    var isbn: String
    var pages: Int
    var exclusiveShelf: String
}

private func parseGoodreadsCSV(_ data: String) -> [GoodreadsRow] {
    var rows: [GoodreadsRow] = []
    let lines = data.components(separatedBy: .newlines).filter { !$0.isEmpty }
    
    guard let headerLine = lines.first else { return [] }
    let headers = splitCSVLine(headerLine).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    
    let titleIdx = headers.firstIndex(of: "Title")
    let authorIdx = headers.firstIndex(of: "Author")
    let isbnIdx = headers.firstIndex(of: "ISBN") ?? headers.firstIndex(of: "ISBN13")
    let pagesIdx = headers.firstIndex(of: "Number of Pages")
    let shelfIdx = headers.firstIndex(of: "Exclusive Shelf")
    
    for line in lines.dropFirst() {
        let columns = splitCSVLine(line)
        guard columns.count > max(titleIdx ?? 0, authorIdx ?? 0) else { continue }
        
        let title = titleIdx != nil && columns.count > titleIdx! ? columns[titleIdx!] : "Unknown"
        let author = authorIdx != nil && columns.count > authorIdx! ? columns[authorIdx!] : "Unknown"
        var isbn = isbnIdx != nil && columns.count > isbnIdx! ? columns[isbnIdx!] : ""
        let pagesStr = pagesIdx != nil && columns.count > pagesIdx! ? columns[pagesIdx!] : "0"
        let shelf = shelfIdx != nil && columns.count > shelfIdx! ? columns[shelfIdx!] : "read"
        
        isbn = isbn.replacingOccurrences(of: "=\"", with: "").replacingOccurrences(of: "\"", with: "")
        
        rows.append(GoodreadsRow(
            title: title.replacingOccurrences(of: "\"", with: ""),
            author: author.replacingOccurrences(of: "\"", with: ""),
            isbn: isbn,
            pages: Int(pagesStr) ?? 0,
            exclusiveShelf: shelf.replacingOccurrences(of: "\"", with: "")
        ))
    }
    return rows
}

private func splitCSVLine(_ line: String) -> [String] {
    var result: [String] = []
    var current = ""
    var inQuotes = false
    
    for char in line {
        if char == "\"" {
            inQuotes.toggle()
        } else if char == "," && !inQuotes {
            result.append(current)
            current = ""
        } else {
            current.append(char)
        }
    }
    result.append(current)
    return result
}
