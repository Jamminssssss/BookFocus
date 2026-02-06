import SwiftUI
import SwiftData
import PhotosUI

struct AddBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - Book basic info
    @State private var title: String = ""
    @State private var author: String = ""
    @State private var totalPages: String = ""

    // MARK: - Cover image
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showCamera = false

    // MARK: - Library loan
    @State private var isLibraryLoan: Bool = false
    @State private var checkoutDate: Date = Date()
    @State private var dueDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date())!

    var body: some View {
        VStack(spacing: 0) {
            AdaptiveTopBannerView()

            NavigationStack {
                Form {
                    // MARK: - Book info
                    Section("Book Information") {
                        TextField("Title", text: $title)
                        TextField("Author", text: $author)
                        TextField("Total Pages", text: $totalPages)
                            .keyboardType(.numberPad)
                    }

                    // MARK: - Cover image
                    Section("Cover Image") {
                        if let selectedImage {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                        }

                        HStack(spacing: 16) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("Gallery", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                showCamera = true
                            } label: {
                                Label("Camera", systemImage: "camera")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // MARK: - Library loan
                    Section("Library Loan") {
                        Toggle("Enable Library Due Reminder", isOn: $isLibraryLoan)

                        if isLibraryLoan {
                            DatePicker(
                                "Checkout Date",
                                selection: $checkoutDate,
                                displayedComponents: .date
                            )

                            DatePicker(
                                "Due Date",
                                selection: $dueDate,
                                in: checkoutDate...,
                                displayedComponents: .date
                            )
                        }
                    }
                }
                .navigationTitle("Add Book")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveBook() }
                            .disabled(!isValid)
                    }
                }
                .onChange(of: selectedPhoto) { _, newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            selectedImage = image
                        }
                    }
                }
                .sheet(isPresented: $showCamera) {
                    ImagePicker(image: $selectedImage, sourceType: .camera)
                        .ignoresSafeArea()
                }
            }

            AdaptiveBottomBannerView()
        }
    }

    // MARK: - Validation
    private var isValid: Bool {
        !title.isEmpty &&
        !author.isEmpty &&
        !totalPages.isEmpty &&
        Int(totalPages) != nil
    }

    // MARK: - Image resize (CloudKit friendly)
    private func resizeImage(_ image: UIImage, targetWidth: CGFloat = 800) -> UIImage {
        let scale = targetWidth / image.size.width
        let newHeight = image.size.height * scale
        let size = CGSize(width: targetWidth, height: newHeight)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func saveBook() {
        guard let pages = Int(totalPages) else { return }

        let imageData: Data? = selectedImage.flatMap {
            let resized = resizeImage($0, targetWidth: 800)
            return resized.jpegData(compressionQuality: 0.7)
        }

        let newBook = Book(
            title: title,
            author: author,
            totalPages: pages,
            coverImageData: imageData,
            checkoutDate: isLibraryLoan ? checkoutDate : nil,
            dueDate: isLibraryLoan ? dueDate : nil
        )

        modelContext.insert(newBook)

        do {
            try modelContext.save()

            // 📱 반납일 알림 설정
            if isLibraryLoan, let dueDate = newBook.dueDate {
                // 같은 날짜 책 모두 가져오기
                let booksDueSameDay = fetchBooks(dueDate: dueDate)

                // Payload 생성
                let payload = WatchDueReminderScheduler.DueGroupPayload(
                    dateKey: Self.dateKeyFormatter.string(from: dueDate),
                    dueDate: dueDate,
                    bookTitles: booksDueSameDay.map { $0.title }
                )

                Task {
                    // iOS 앱 자체 알림
                    await WatchDueReminderScheduler.scheduleGroup(payload)
                    
                    // ⌚️ 워치로 그룹 알림 전송
                    WatchSyncManager.shared.sendDueReminderGroupToWatch(payload)
                }
            }

            syncAllBooksToWatch()
            dismiss()
        } catch {
            print("❌ Failed to save book:", error)
        }
    }

    // 같은 날짜 책 모두 가져오기
    private func fetchBooks(dueDate: Date) -> [Book] {
        do {
            // SwiftData FetchDescriptor 사용
            let descriptor = FetchDescriptor<Book>(
                predicate: #Predicate { $0.dueDate == dueDate }
            )
            return try modelContext.fetch(descriptor)
        } catch {
            print("❌ Failed to fetch books for dueDate:", error)
            return []
        }
    }



    // MARK: - DateFormatter for WatchDueReminderScheduler
    private static let dateKeyFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()


    // MARK: - Watch sync
    private func syncAllBooksToWatch() {
        let fetchDescriptor = FetchDescriptor<Book>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        do {
            let allBooks = try modelContext.fetch(fetchDescriptor)
            let bookDataList = allBooks.map { book in
                TimerStateManager.BookData(
                    id: book.id.uuidString,
                    title: book.title,
                    author: book.author,
                    totalPages: book.totalPages,
                    currentPage: book.currentPage,
                    createdAt: book.createdAt,
                    lastUpdated: book.lastUpdated
                )
            }

            WatchSyncManager.shared.sendBooksToWatch(bookDataList)
            print("✅ Synced \(bookDataList.count) books to Watch")
        } catch {
            print("❌ Failed to fetch books:", error)
        }
    }
}
