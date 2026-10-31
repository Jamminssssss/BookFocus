import SwiftUI

// MARK: - 검색 범위 필터 Enum
enum BookSearchScope: String, CaseIterable {
    case all = "all"
    case title = "title"
    case author = "author"
    
    var queryPrefix: String {
        switch self {
        case .all: return ""
        case .title: return "intitle:"
        case .author: return "inauthor:"
        }
    }
}

// 필터 모드 (전체 / 종이책 우선 / 전자책 우선)
enum GoogleBookFilterMode: String, CaseIterable {
    case all = "All"
    case physicalOnly = "Paper Book"
    case ebooksOnly = "eBook"
}

struct BookSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // ⭐️ 이전 화면에서 선택된 포맷 저장
    private let targetFormat: BookFormat
    
    @State private var searchText = ""
    @State private var selectedScope: BookSearchScope = .all
    @State private var filterMode: GoogleBookFilterMode
    
    // API 원본 결과와 화면에 보여줄 결과를 분리 관리
    @State private var rawFetchedBooks: [SearchBookResult] = []
    @State private var displayedBooks: [SearchBookResult] = []
    
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    
    var onBookSelected: (SearchBookResult) -> Void
    
    init(initialFormat: BookFormat = .physical, onBookSelected: @escaping (SearchBookResult) -> Void) {
        self.targetFormat = initialFormat
        self.onBookSelected = onBookSelected
        _filterMode = State(initialValue: initialFormat == .ebook ? .ebooksOnly : .physicalOnly)
    }
    
    private var apiKey: String { GoogleBooksConfiguration.apiKey }
    
    var paperColor: Color { colorScheme == .dark ? Color.black : Color(red: 0.98, green: 0.97, blue: 0.95) }
    var inkColor: Color { colorScheme == .dark ? Color.white : Color.black }
    
    var body: some View {
        NavigationStack {
            ZStack {
                paperColor.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // MARK: - Custom Header
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.title2).foregroundStyle(inkColor) }
                        Spacer()
                        Text("search.").font(.custom("ChalkboardSE-Bold", size: 20)).foregroundStyle(inkColor)
                        Spacer()
                        Image(systemName: "xmark").font(.title2).opacity(0)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 16)
                    
                    // MARK: - Search Bar & Filters
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(inkColor)
                            TextField(filterMode == .ebooksOnly ? "search e-books..." : "title or author...", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.custom("ChalkboardSE-Regular", size: 16))
                                .foregroundStyle(inkColor)
                        }
                        .padding(16)
                        .overlay(RoundedRectangle(cornerRadius: 25).stroke(inkColor, lineWidth: 1.5))
                        
                        // 상단 필터 UI
                        HStack(spacing: 8) {
                            ForEach(GoogleBookFilterMode.allCases, id: \.self) { mode in
                                Button {
                                    filterMode = mode
                                    applyLocalFilter() // ⭐️ 필터 클릭 시 즉시 영리하게 재정렬
                                } label: {
                                    HStack(spacing: 4) {
                                        if mode == .ebooksOnly { Image(systemName: "ipad.landscape").font(.caption) }
                                        if mode == .physicalOnly { Image(systemName: "book.closed").font(.caption) }
                                        Text(mode.rawValue).font(.custom(filterMode == mode ? "ChalkboardSE-Bold" : "ChalkboardSE-Regular", size: 13))
                                    }
                                    .foregroundStyle(filterMode == mode ? paperColor : inkColor)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(filterMode == mode ? inkColor : Color.clear, in: Capsule())
                                    .overlay(Capsule().stroke(inkColor, lineWidth: 1.2))
                                }
                            }
                            
                            Rectangle().fill(inkColor.opacity(0.3)).frame(width: 1, height: 18).padding(.horizontal, 2)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(BookSearchScope.allCases, id: \.self) { scope in
                                        Button {
                                            selectedScope = scope
                                            triggerSearch()
                                        } label: {
                                            Text(scope.rawValue)
                                                .font(.custom(selectedScope == scope ? "ChalkboardSE-Bold" : "ChalkboardSE-Regular", size: 13))
                                                .foregroundStyle(selectedScope == scope ? paperColor : inkColor)
                                                .padding(.horizontal, 12).padding(.vertical, 6)
                                                .background(selectedScope == scope ? inkColor : Color.clear, in: Capsule())
                                                .overlay(Capsule().stroke(inkColor, lineWidth: 1.2))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 24).padding(.bottom, 16)
                    
                    // MARK: - Results Area
                    if isSearching {
                        Spacer(); ProgressView().tint(inkColor); Text("searching...").font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor).padding(.top, 8); Spacer()
                    } else if let error = errorMessage {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 50, weight: .light)).foregroundColor(inkColor)
                        Text(error).font(.custom("ChalkboardSE-Regular", size: 16)).foregroundColor(inkColor).multilineTextAlignment(.center).padding()
                        Button("try again") { Task { await performSearch() } }.font(.custom("ChalkboardSE-Bold", size: 16)).foregroundStyle(inkColor).padding(.horizontal, 24).padding(.vertical, 12).overlay(RoundedRectangle(cornerRadius: 25).stroke(inkColor, lineWidth: 1.5))
                        Spacer()
                    } else if displayedBooks.isEmpty && !searchText.isEmpty {
                        Spacer()
                        Image(systemName: "questionmark.folder").font(.system(size: 50, weight: .light)).foregroundColor(inkColor.opacity(0.5))
                        Text("no books found.").font(.custom("ChalkboardSE-Regular", size: 18)).foregroundColor(inkColor).padding(.top, 8)
                        Spacer()
                    } else if displayedBooks.isEmpty {
                        Spacer()
                        Image(systemName: "books.vertical").font(.system(size: 50, weight: .light)).foregroundColor(inkColor.opacity(0.5))
                        Text("type to search.").font(.custom("ChalkboardSE-Regular", size: 18)).foregroundColor(inkColor).padding(.top, 8)
                        Spacer()
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 16) {
                                ForEach(displayedBooks) { book in
                                    // ⭐️ 현재 선택한 포맷과 호환 여부 판단
                                    let isCompatible = (targetFormat == .ebook && book.isEbook) || (targetFormat == .physical && !book.isEbook)
                                    
                                    BookSearchRow(book: book, inkColor: inkColor, paperColor: paperColor)
                                        .opacity(isCompatible ? 1.0 : 0.4) // 불일치 도서는 시각적으로 구분
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            // ⭐️ 선택한 포맷과 다른 도서 선택 차단
                                            if targetFormat == .physical && book.isEbook {
                                                errorMessage = "전자책(eBook) 항목입니다. 종이책 모드에서는 선택할 수 없습니다."
                                                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                                return
                                            }
                                            if targetFormat == .ebook && !book.isEbook {
                                                errorMessage = "종이책 항목입니다. 전자책 모드에서는 선택할 수 없습니다."
                                                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                                return
                                            }
                                            
                                            onBookSelected(book)
                                        }
                                }
                            }
                            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .onChange(of: searchText) { _, _ in triggerSearch() }
        }
    }
    
    private func triggerSearch() {
        searchTask?.cancel()
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            rawFetchedBooks = []
            displayedBooks = []
            errorMessage = nil
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if !Task.isCancelled { await performSearch() }
        }
    }
    
    private func performSearch() async {
        let cleanText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        let requestedScope = selectedScope
        isSearching = true
        errorMessage = nil

        do {
            let results = try await BookSearchService().search(
                text: cleanText,
                queryPrefix: requestedScope.queryPrefix,
                apiKey: apiKey,
                targetIsEbook: targetFormat == .ebook
            )
            try Task.checkCancellation()
            guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == cleanText,
                  selectedScope == requestedScope else { return }

            rawFetchedBooks = results
            applyLocalFilter()
            isSearching = false
        } catch is CancellationError {
            // 새 검색어가 입력되면서 취소된 정상적인 요청이다.
        } catch {
            guard searchText.trimmingCharacters(in: .whitespacesAndNewlines) == cleanText,
                  selectedScope == requestedScope else { return }
            rawFetchedBooks = []
            displayedBooks = []
            isSearching = false
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Book search is temporarily unavailable. Please try again."
        }
    }
    
    private func applyLocalFilter() {
        let cleanText = searchText.trimmingCharacters(in: .whitespaces)
        guard !cleanText.isEmpty else { return }
        
        let lowerQuery = cleanText.lowercased()
        var sortedBooks = rawFetchedBooks
        
        sortedBooks.sort { book1, book2 in
            let match1 = book1.title.lowercased().contains(lowerQuery) || book1.authors.lowercased().contains(lowerQuery)
            let match2 = book2.title.lowercased().contains(lowerQuery) || book2.authors.lowercased().contains(lowerQuery)
            
            if match1 != match2 {
                return match1
            }
            
            if filterMode == .ebooksOnly {
                if book1.isEbook != book2.isEbook { return book1.isEbook }
            } else if filterMode == .physicalOnly {
                if book1.isEbook != book2.isEbook { return !book1.isEbook }
            }
            
            return false
        }
        
        self.displayedBooks = sortedBooks
    }
}

// MARK: - Search Result Row
struct BookSearchRow: View {
    let book: SearchBookResult
    let inkColor: Color
    let paperColor: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let url = book.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty: ProgressView().tint(inkColor)
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure: placeholderImage
                        @unknown default: placeholderImage
                        }
                    }
                } else { placeholderImage }
            }
            .frame(width: 50, height: 75)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(inkColor, lineWidth: 1.5))
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(book.title).font(.custom("ChalkboardSE-Bold", size: 16)).foregroundStyle(inkColor).lineLimit(2)
                }
                
                Text(book.authors).font(.custom("ChalkboardSE-Regular", size: 14)).foregroundColor(inkColor.opacity(0.7)).lineLimit(1)
                
                HStack(spacing: 8) {
                    if book.isEbook {
                        Text("[eBook]")
                            .font(.custom("ChalkboardSE-Bold", size: 11))
                            .foregroundColor(paperColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(inkColor, in: RoundedRectangle(cornerRadius: 4))
                    } else if book.pageCount > 0 {
                        Text("\(book.pageCount) p").font(.custom("ChalkboardSE-Regular", size: 12)).foregroundColor(inkColor.opacity(0.5))
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
    }
    
    private var placeholderImage: some View {
        paperColor.overlay(Image(systemName: "book").foregroundColor(inkColor.opacity(0.5)))
    }
}
