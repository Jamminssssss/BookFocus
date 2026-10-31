import SwiftUI
import SwiftData
import PhotosUI

struct AddBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme // 다크모드 대응

    @StateObject private var storeManager = StoreKitManager.shared
    @State private var showPremiumSheet = false

    // MARK: - Book basic info
    @State private var title: String = ""
    @State private var author: String = ""
    @State private var totalPages: String = ""
    @State private var bookFormat: BookFormat = .physical // ⭐️ 포맷 상태

    // MARK: - Cover image
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showCamera = false
    @State private var showBarcodeScanner = false
    
    // MARK: - Search
    @State private var showSearchSheet = false
    
    // MARK: - API Loading
    @State private var isLoadingBookInfo = false
    @State private var bookInfoError: String?
    @State private var lastScannedISBN: String?

    // MARK: - Library loan
    @State private var isLibraryLoan: Bool = false
    @State private var checkoutDate: Date = Date()
    @State private var dueDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date())!

    // 다크모드 색상
    var paperColor: Color { colorScheme == .dark ? Color.black : Color(red: 0.98, green: 0.97, blue: 0.95) }
    var inkColor: Color { colorScheme == .dark ? Color.white : Color.black }

    var body: some View {
        NavigationStack {
            ZStack {
                paperColor.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // MARK: - 커스텀 아날로그 헤더
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.title2).foregroundStyle(inkColor)
                        }
                        Spacer()
                        Text("add book.").font(.custom("ChalkboardSE-Bold", size: 20)).foregroundStyle(inkColor)
                        Spacer()
                        Button { saveBook() } label: {
                            Image(systemName: "checkmark").font(.title2)
                                .foregroundStyle(isValid ? inkColor : inkColor.opacity(0.3))
                        }
                        .disabled(!isValid)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            
                            // MARK: - 검색 버튼
                            Button { showSearchSheet = true } label: {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text(bookFormat == .ebook ? "search e-book online..." : "search book online...")
                                    Spacer()
                                }
                                .font(.custom("ChalkboardSE-Regular", size: 16))
                                .foregroundStyle(inkColor)
                                .padding(16)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                            }
                            .padding(.horizontal, 24)
                            
                            if isLoadingBookInfo {
                                HStack {
                                    ProgressView().tint(inkColor)
                                    Text("Loading book information...").font(.custom("ChalkboardSE-Regular", size: 14)).foregroundColor(inkColor.opacity(0.7))
                                }
                            }
                            if let error = bookInfoError {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle")
                                    Text(error).font(.custom("ChalkboardSE-Regular", size: 14))
                                }.foregroundColor(inkColor)
                            }
                            
                            // MARK: - 도서 정보 입력란
                            VStack(alignment: .leading, spacing: 16) {
                                Text("info.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                
                                // ⭐️ 책 포맷 선택 버튼 (Paper Book vs E-Book)
                                HStack(spacing: 12) {
                                    formatSelectButton(titleKey: "Paper Book", icon: "book.closed", targetFormat: .physical)
                                    formatSelectButton(titleKey: "E-Book", icon: "ipad.landscape", targetFormat: .ebook)
                                }
                                
                                TextField("title", text: $title)
                                    .textFieldStyle(.plain).font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor).padding(16)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                
                                TextField("author", text: $author)
                                    .textFieldStyle(.plain).font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor).padding(16)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                
                                // ⭐️ 전자책일 땐 페이지 입력 대신 100% 안내문 표시
                                if bookFormat == .physical {
                                    TextField("total pages", text: $totalPages).keyboardType(.numberPad)
                                        .textFieldStyle(.plain).font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor).padding(16)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                } else {
                                    HStack {
                                        Image(systemName: "percent")
                                        Text("E-book progress is tracked from \(0.0.formatted(.percent.precision(.fractionLength(0)))) to \(1.0.formatted(.percent.precision(.fractionLength(0)))).")
                                            .font(.custom("ChalkboardSE-Regular", size: 14))
                                    }
                                    .foregroundStyle(inkColor.opacity(0.7)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                                }
                            }
                            .padding(.horizontal, 24)
                            
                            // MARK: - 표지 이미지
                            VStack(alignment: .leading, spacing: 16) {
                                Text("cover.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                
                                if let selectedImage {
                                    Image(uiImage: selectedImage)
                                        .resizable().scaledToFit().frame(height: 200).frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 2))
                                } else {
                                    Rectangle().fill(Color.clear).frame(height: 150)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                                        .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(inkColor.opacity(0.3)))
                                }

                                HStack(spacing: 12) {
                                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                        VStack(spacing: 6) { Image(systemName: "photo").font(.title3); Text("gallery").font(.custom("ChalkboardSE-Regular", size: 12)) }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(inkColor).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                    }
                                    
                                    Button { showCamera = true } label: {
                                        VStack(spacing: 6) { Image(systemName: "camera").font(.title3); Text("camera").font(.custom("ChalkboardSE-Regular", size: 12)) }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(inkColor).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                    }
                                    
                                    Button { showBarcodeScanner = true } label: {
                                        VStack(spacing: 6) { Image(systemName: "barcode.viewfinder").font(.title3); Text("barcode").font(.custom("ChalkboardSE-Regular", size: 12)) }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(inkColor).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                    }
                                    .disabled(isLoadingBookInfo)
                                }
                            }
                            .padding(.horizontal, 24)

                            // MARK: - 도서관 대출 기한
                            VStack(alignment: .leading, spacing: 16) {
                                Toggle(isOn: $isLibraryLoan) {
                                    Text("library loan.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                }.tint(inkColor)
                                
                                if isLibraryLoan {
                                    VStack(spacing: 12) {
                                        DatePicker("checkout", selection: $checkoutDate, displayedComponents: .date)
                                            .font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor).colorMultiply(inkColor)
                                        DatePicker("due date", selection: $dueDate, in: checkoutDate..., displayedComponents: .date)
                                            .font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor).colorMultiply(inkColor)
                                    }
                                    .padding(16).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                        }
                        .padding(.top, 16)
                    }
                }
            }
            .navigationBarHidden(true)
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        selectedImage = image
                    }
                }
            }
            .fullScreenCover(isPresented: $showPremiumSheet) { PurchaseView() }
            .fullScreenCover(isPresented: $showCamera) { ImagePicker(image: $selectedImage, sourceType: .camera).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showBarcodeScanner) {
                BarcodeScannerView { isbn in
                    showBarcodeScanner = false
                    handleBarcodeDetection(isbn: isbn)
                }
            }
            // ⭐️ 초기 검색 모드에 포맷 전달
            .fullScreenCover(isPresented: $showSearchSheet) {
                BookSearchView(initialFormat: bookFormat) { selectedBook in
                    showSearchSheet = false
                    fillBookInfo(from: selectedBook)
                }
            }
        }
    }

    private func formatSelectButton(titleKey: LocalizedStringKey, icon: String, targetFormat: BookFormat) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                // ⭐️ 수정: 이북에서 종이책으로 전환 시 100페이지로 남아있는 현상 완벽 방지
                if targetFormat == .ebook {
                    bookFormat = .ebook
                    totalPages = "100"
                } else {
                    bookFormat = .physical
                    if totalPages == "100" {
                        totalPages = ""
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(titleKey).font(.custom("ChalkboardSE-Bold", size: 14))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(bookFormat == targetFormat ? inkColor.opacity(1) : Color.clear)
            .foregroundStyle(bookFormat == targetFormat ? paperColor : inkColor)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
        }
    }

    // MARK: - Validation
    private var isValid: Bool {
        if bookFormat == .ebook { return !title.isEmpty && !author.isEmpty }
        else { return !title.isEmpty && !author.isEmpty && !totalPages.isEmpty && Int(totalPages) != nil }
    }
    
    // MARK: - Fill Book Info from Search
    private func fillBookInfo(from book: SearchBookResult) {
        title = book.title
        author = book.authors
        
        // ⭐️ 수정: 선택된 포맷 유지 및 페이지 수 누락 시 상세 조회 API 자동 2차 호출
        if bookFormat == .ebook {
            totalPages = "100"
        } else {
            if book.pageCount > 0 {
                totalPages = "\(book.pageCount)"
            } else {
                totalPages = ""
                // 검색 목록 요약 정보에 페이지 수가 누락된 경우 상세 정보 조회 로직 가동
                fetchDetailedPageCount(book: book)
            }
        }
        
        if let imageURL = book.imageURL { downloadImage(from: imageURL) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // ⭐️ 추가: 구글 API 상세 조회 및 Open Library API 3차 폴백을 통한 페이지 수 자동 채우기
    private func fetchDetailedPageCount(book: SearchBookResult) {
        guard bookFormat == .physical && book.pageCount <= 0 else { return }
        isLoadingBookInfo = true

        // Open Library 보완 검색 결과의 ID는 Google volume ID가 아니다.
        guard !book.id.hasPrefix("openlibrary:") else {
            fetchFallbackPageCountFromOpenLibrary(title: book.title, author: book.authors)
            return
        }
        
        let apiKey = GoogleBooksConfiguration.apiKey
        let keyQuery = apiKey.isEmpty ? "" : "?key=\(apiKey)"
        let urlString = "https://www.googleapis.com/books/v1/volumes/\(book.id)\(keyQuery)"
        
        guard let url = URL(string: urlString) else {
            fetchFallbackPageCountFromOpenLibrary(title: book.title, author: book.authors)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let result = try? JSONDecoder().decode(VolumeDetailResponse.self, from: data),
                   let pages = result.volumeInfo?.pageCount, pages > 0 {
                    self.totalPages = "\(pages)"
                    self.isLoadingBookInfo = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    // 구글 상세 조회에도 페이지가 없으면 Open Library 무료 API로 3차 조회
                    self.fetchFallbackPageCountFromOpenLibrary(title: book.title, author: book.authors)
                }
            }
        }.resume()
    }
    
    private func fetchFallbackPageCountFromOpenLibrary(title: String, author: String) {
        var components = URLComponents(string: "https://openlibrary.org/search.json")
        var queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "limit", value: "3")
        ]
        if !author.isEmpty && author != "Unknown Author" {
            queryItems.append(URLQueryItem(name: "author", value: author))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            self.isLoadingBookInfo = false
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                self.isLoadingBookInfo = false
                if let data = data,
                   let result = try? JSONDecoder().decode(OpenLibraryResponse.self, from: data),
                   let pages = result.docs?.compactMap({ $0.number_of_pages_median }).first(where: { $0 > 0 }) {
                    self.totalPages = "\(pages)"
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }.resume()
    }

    // MARK: - Barcode Detection Handler
    private func handleBarcodeDetection(isbn: String) {
        guard lastScannedISBN != isbn else {
            bookInfoError = NSLocalizedString("This book was just scanned. Please scan a different book.", comment: "Barcode duplicate scan error")
            return
        }
        lastScannedISBN = isbn; fetchBookInfo(isbn: isbn)
    }

    // MARK: - Google Books API (ISBN)
    private func fetchBookInfo(isbn: String) {
        guard !isLoadingBookInfo else { return }
        isLoadingBookInfo = true; bookInfoError = nil
        let apiKey = GoogleBooksConfiguration.apiKey
        let keyQuery = apiKey.isEmpty ? "" : "&key=\(apiKey)"
        let urlString = "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)\(keyQuery)"
        guard let url = URL(string: urlString) else {
            bookInfoError = NSLocalizedString("Invalid URL format", comment: "")
            isLoadingBookInfo = false; return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoadingBookInfo = false
                if let error = error {
                    bookInfoError = (error as NSError).code == NSURLErrorTimedOut ? NSLocalizedString("Request timed out.", comment: "") : NSLocalizedString("Network error", comment: "")
                    return
                }
                guard let data = data else {
                    bookInfoError = NSLocalizedString("No data received from server", comment: "")
                    return
                }
                do {
                    let result = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
                    if let book = result.items?.first?.volumeInfo {
                        let isGoogleEbook = result.items?.first?.saleInfo?.isEbook ?? false
                        
                        // ⭐️ 선택된 포맷과 불일치할 경우 바코드 추가 차단 (다국어 처리 완료)
                        if bookFormat == .physical && isGoogleEbook {
                            bookInfoError = NSLocalizedString("The scanned book is an e-Book. Cannot add in Paper Book mode.", comment: "")
                            lastScannedISBN = nil
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            return
                        }
                        if bookFormat == .ebook && !isGoogleEbook {
                            bookInfoError = NSLocalizedString("The scanned book is a paper book. Cannot add in E-Book mode.", comment: "")
                            lastScannedISBN = nil
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            return
                        }
                        
                        title = book.title ?? ""
                        author = book.authors?.joined(separator: ", ") ?? ""
                        
                        if bookFormat == .ebook {
                            totalPages = "100"
                        } else if let pageCount = book.pageCount, pageCount > 0 {
                            totalPages = "\(pageCount)"
                        }
                        
                        if let thumbnailURL = book.imageLinks?.thumbnail, let imageURL = URL(string: thumbnailURL.replacingOccurrences(of: "http://", with: "https://")) {
                            downloadImage(from: imageURL)
                        }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } else {
                        let notFoundFormat = NSLocalizedString("No book found for ISBN: %@", comment: "")
                        bookInfoError = String(format: notFoundFormat, isbn)
                        lastScannedISBN = nil
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    }
                } catch {
                    bookInfoError = NSLocalizedString("Failed to parse book data", comment: "")
                }
            }
        }.resume()
    }
    
    private func downloadImage(from url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async { selectedImage = image }
        }.resume()
    }

    private func resizeImage(_ image: UIImage, targetWidth: CGFloat = 800) -> UIImage {
        let scale = targetWidth / image.size.width; let size = CGSize(width: targetWidth, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    private func saveBook() {
        // Recheck at save time in case another device added a book or the subscription expired.
        let currentBookCount: Int
        do {
            currentBookCount = try modelContext.fetchCount(FetchDescriptor<Book>())
        } catch {
            bookInfoError = NSLocalizedString("Failed to save book", comment: "")
            return
        }
        guard FreeLimitManager.shared.canAddBook(isPremium: storeManager.isPremium, currentBookCount: currentBookCount) else {
            showPremiumSheet = true
            return
        }
        let pages = bookFormat == .ebook ? 100 : (Int(totalPages) ?? 0)
        let imageData: Data? = selectedImage.flatMap { resizeImage($0, targetWidth: 800).jpegData(compressionQuality: 0.7) }
        let newBook = Book(title: title, author: author, totalPages: pages, format: bookFormat, coverImageData: imageData, checkoutDate: isLibraryLoan ? checkoutDate : nil, dueDate: isLibraryLoan ? dueDate : nil)
        modelContext.insert(newBook)

        do {
            try modelContext.save()
            
            // 🔥 [추가 완료]: 도서관 대출 설정 시 캘린더 대출일 / 반납 예정일에 이벤트 등록 (중복 방지 덮어쓰기)
            if isLibraryLoan {
                LoanCalendarManager.shared.updateLoanEvents(
                    bookID: newBook.id.uuidString,
                    title: newBook.title,
                    author: newBook.author,
                    checkoutDate: newBook.checkoutDate,
                    dueDate: newBook.dueDate
                )
            } else {
                LoanCalendarManager.shared.removeLoanEvents(forBookID: newBook.id.uuidString)
            }

            if isLibraryLoan, let dueDate = newBook.dueDate {
                let booksDueSameDay = fetchBooks(dueDate: dueDate)
                let payload = WatchDueReminderScheduler.DueGroupPayload(dateKey: Self.dateKeyFormatter.string(from: dueDate), dueDate: dueDate, bookTitles: booksDueSameDay.map { $0.title })
                Task { await WatchDueReminderScheduler.scheduleGroup(payload); WatchSyncManager.shared.sendDueReminderGroupToWatch(payload) }
            }
            syncAllBooksToWatch()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            modelContext.delete(newBook)
            bookInfoError = NSLocalizedString("Failed to save book", comment: "")
        }
    }

    private func fetchBooks(dueDate: Date) -> [Book] {
        do {
            return try modelContext.fetch(FetchDescriptor<Book>()).filter {
                $0.loanStatus != .returned
                    && $0.dueDate.map { Calendar.current.isDate($0, inSameDayAs: dueDate) } == true
            }
        } catch { return [] }
    }
    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    // ⭐️ 200% 방어코드: syncAllBooksToWatch에서 format: $0.formatRawValue 명시적 전달
    private func syncAllBooksToWatch() {
        do {
            let allBooks = try modelContext.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
            WatchSyncManager.shared.sendBooksToWatch(
                allBooks.map { TimerStateManager.BookData.from($0) },
                isFullSnapshot: true
            )
        } catch {}
    }
}

// MARK: - Google Books & Fallback API Models
struct GoogleBooksResponse: Codable { let items: [BookItem]? }
struct BookItem: Codable {
    let id: String? // ⭐️ 상세 페이지 조회를 위해 ID 추가
    let volumeInfo: VolumeInfo
    let saleInfo: SaleInfo?
}
struct VolumeInfo: Codable {
    let title: String?
    let authors: [String]?
    let pageCount: Int?
    let imageLinks: ImageLinks?
}
struct SaleInfo: Codable {
    let isEbook: Bool?
}
struct ImageLinks: Codable { let thumbnail: String? }
struct SearchBookResult: Identifiable {
    let id: String
    let title: String
    let authors: String
    let pageCount: Int
    let imageURL: URL?
    let thumbnailData: Data?
    let isEbook: Bool
}
struct VolumeDetailResponse: Codable {
    let volumeInfo: VolumeInfo?
}
struct OpenLibraryResponse: Codable {
    let docs: [OpenLibraryDoc]?
}
struct OpenLibraryDoc: Codable {
    let number_of_pages_median: Int?
}
