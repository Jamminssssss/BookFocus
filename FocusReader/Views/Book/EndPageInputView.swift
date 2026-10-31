import SwiftUI
import SwiftData
import PhotosUI

struct EndPageInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let book: Book
    let session: ReadingSession?
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @StateObject private var storeManager = StoreKitManager.shared
    @State private var showPurchaseSheet = false
    
    @State private var endPage: String = ""
    @State private var memo: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    // MARK: - Cover Image States (기존 책 표지 업데이트용)
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var tempImage: UIImage?
    @State private var showCamera = false
    
    // MARK: - ⭐️ Memo Image States (새로 추가된 메모 사진용)
    @State private var memoPhoto: PhotosPickerItem?
    @State private var memoImage: UIImage?
    @State private var showMemoCamera = false
    
    @State private var updateLibraryLoan: Bool = false
    @State private var newCheckoutDate: Date = Date()
    @State private var newDueDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
    @State private var currentLoanStatus: LoanStatus = .none
    
    private var startPage: Int { session?.startPage ?? book.currentPage }
    
    var paperColor: Color { colorScheme == .dark ? Color.black : Color(red: 0.98, green: 0.97, blue: 0.95) }
    var inkColor: Color { colorScheme == .dark ? Color.white : Color.black }
    
    var body: some View {
        NavigationStack {
            ZStack {
                paperColor.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // MARK: - Custom Header
                    HStack {
                        Button {
                            TimerStateManager.shared.clearState()
                            NotificationCenter.default.post(name: Notification.Name("ReadingTimer.EndLiveActivity"), object: nil)
                            dismiss(); onCancel()
                        } label: {
                            Image(systemName: "xmark").font(.title2).foregroundStyle(inkColor)
                        }
                        Spacer()
                        Text("end session.").font(.custom("ChalkboardSE-Bold", size: 20)).foregroundStyle(inkColor)
                        Spacer()
                        Button { saveSession() } label: {
                            Image(systemName: "checkmark").font(.title2).foregroundStyle(endPage.trimmingCharacters(in: .whitespaces).isEmpty ? inkColor.opacity(0.3) : inkColor)
                        }
                        .disabled(endPage.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            
                            // MARK: - Book Info
                            VStack(spacing: 6) {
                                Text(book.title).font(.custom("ChalkboardSE-Bold", size: 22)).foregroundStyle(inkColor).multilineTextAlignment(.center)
                                Text(book.author).font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor.opacity(0.7))
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                            
                            // MARK: - Page Input
                            VStack(alignment: .leading, spacing: 16) {
                                Text("page. (start: \(startPage))").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                TextField("end page", text: $endPage)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.plain)
                                    .font(.custom("ChalkboardSE-Regular", size: 16))
                                    .foregroundStyle(inkColor)
                                    .padding(16)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                            }
                            .padding(.horizontal, 24)
                            
                            // MARK: - ⭐️ Memo Photo (메모용 사진 추가 섹션)
                            VStack(alignment: .leading, spacing: 16) {
                                Text("captured page.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                
                                if let memoImage {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: memoImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 200)
                                            .frame(maxWidth: .infinity)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                            .clipped()
                                        
                                        Button { self.memoImage = nil } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title2)
                                                .foregroundStyle(inkColor)
                                                .background(Circle().fill(paperColor))
                                        }
                                        .padding(8)
                                    }
                                } else {
                                    Rectangle().fill(Color.clear).frame(height: 120)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                                        .overlay(Image(systemName: "camera.dashed").font(.largeTitle).foregroundStyle(inkColor.opacity(0.3)))
                                }
                                
                                HStack(spacing: 12) {
                                    PhotosPicker(selection: $memoPhoto, matching: .images) {
                                        analogButtonLabel(title: "gallery", icon: "photo")
                                    }
                                    
                                    Button { showMemoCamera = true } label: {
                                        analogButtonLabel(title: "camera", icon: "camera")
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            
                            // MARK: - Memo Text
                            VStack(alignment: .leading, spacing: 16) {
                                Text("memo.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                TextEditor(text: $memo)
                                    .font(.custom("ChalkboardSE-Regular", size: 16))
                                    .foregroundStyle(inkColor)
                                    .scrollContentBackground(.hidden)
                                    .padding(12)
                                    .frame(minHeight: 120)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                            }
                            .padding(.horizontal, 24)
                            
                            // MARK: - Update Cover (표지 업데이트)
                            VStack(alignment: .leading, spacing: 16) {
                                Text("update cover.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                
                                if let uiImage = selectedImage ?? tempImage ?? (book.coverImageData.flatMap { UIImage(data: $0) }) {
                                    Image(uiImage: uiImage)
                                        .resizable().scaledToFit().frame(height: 150)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 2))
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Rectangle().fill(Color.clear).frame(height: 100)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                                        .overlay(Text("no image").font(.custom("ChalkboardSE-Regular", size: 14)).foregroundStyle(inkColor.opacity(0.5)))
                                }
                                
                                HStack(spacing: 12) {
                                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                        analogButtonLabel(title: "gallery", icon: "photo")
                                    }
                                    Button { showCamera = true } label: {
                                        analogButtonLabel(title: "camera", icon: "camera")
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            
                            // MARK: - Library Status
                            VStack(alignment: .leading, spacing: 16) {
                                Text("library status.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                
                                HStack(spacing: 12) {
                                    Button {
                                        withAnimation { currentLoanStatus = (currentLoanStatus == .returned ? .borrowed : .returned) }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: currentLoanStatus == .returned ? "checkmark.square.fill" : "square")
                                            Text("Mark Returned").font(.custom("ChalkboardSE-Bold", size: 14))
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(currentLoanStatus == .returned ? inkColor.opacity(0.12) : Color.clear)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                        .foregroundStyle(inkColor)
                                    }
                                    
                                    Button {
                                        withAnimation { currentLoanStatus = (currentLoanStatus == .renewed ? .borrowed : .renewed) }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: currentLoanStatus == .renewed ? "checkmark.square.fill" : "square")
                                            Text("Mark Renewed").font(.custom("ChalkboardSE-Bold", size: 14))
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(currentLoanStatus == .renewed ? inkColor.opacity(0.12) : Color.clear)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                        .foregroundStyle(inkColor)
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            
                            // MARK: - Library Loan Update
                            if book.hasDueDate {
                                VStack(alignment: .leading, spacing: 16) {
                                    Toggle(isOn: $updateLibraryLoan) {
                                        Text("update loan date.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                    }.tint(inkColor)
                                    
                                    if updateLibraryLoan {
                                        VStack(spacing: 12) {
                                            DatePicker("checkout", selection: $newCheckoutDate, displayedComponents: .date)
                                                .colorMultiply(inkColor).font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor)
                                            DatePicker("due date", selection: $newDueDate, in: newCheckoutDate..., displayedComponents: .date)
                                                .colorMultiply(inkColor).font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor)
                                        }
                                        .padding(16)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                            
                            Spacer().frame(height: 40)
                        }
                        .padding(.top, 16)
                    }
                }
            }
            .navigationBarHidden(true)
            .alert("Oops", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage) }
            // ⭐️ 카메라 모달: 책 표지 업데이트 용
            .fullScreenCover(isPresented: $showCamera) { ImagePicker(image: $selectedImage, sourceType: .camera).ignoresSafeArea() }
            // ⭐️ 카메라 모달: 메모 사진 캡처 용
            .fullScreenCover(isPresented: $showMemoCamera) { ImagePicker(image: $memoImage, sourceType: .camera).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showPurchaseSheet) { PurchaseView() }
            // 표지 갤러리 로딩
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        selectedImage = image; tempImage = image
                    }
                }
            }
            // 메모 갤러리 로딩
            .onChange(of: memoPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        memoImage = image
                    }
                }
            }
            .onChange(of: selectedImage) { _, newValue in if let image = newValue { tempImage = image } }
            .onAppear {
                if let checkout = book.checkoutDate { newCheckoutDate = checkout }
                if let due = book.dueDate { newDueDate = due }
                currentLoanStatus = book.loanStatus
            }
        }
        .onDisappear {
            TimerStateManager.shared.clearState()
            NotificationCenter.default.post(name: Notification.Name("ReadingTimer.EndLiveActivity"), object: nil)
        }
    }
    
    private func analogButtonLabel(title: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.custom("ChalkboardSE-Regular", size: 12))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .foregroundStyle(inkColor)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
    }
    
    private func resizeImage(_ image: UIImage, targetWidth: CGFloat = 800) -> UIImage {
        let scale = targetWidth / image.size.width; let size = CGSize(width: targetWidth, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
    
    private func saveSession() {
        let trimmed = endPage.trimmingCharacters(in: .whitespaces)
        guard let endPageInt = Int(trimmed) else { errorMessage = "Please enter a valid page number."; showError = true; return }
        guard endPageInt >= startPage else { errorMessage = "End page must be >= start page."; showError = true; return }
        guard endPageInt <= book.totalPages else { errorMessage = "End page cannot exceed total pages."; showError = true; return }
        if updateLibraryLoan && newCheckoutDate > newDueDate { errorMessage = "Due date must be after checkout date."; showError = true; return }
        
        if let session = session { session.finalize(endPage: endPageInt, measuredDuration: session.duration) }
        book.currentPage = endPageInt; book.checkCompletion()
        book.loanStatus = currentLoanStatus
        
        // ⭐️ 메모 저장: 텍스트가 있거나 이미지가 있으면 생성
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMemo.isEmpty || memoImage != nil {
            let memoImageData: Data? = memoImage.flatMap { resizeImage($0, targetWidth: 800).jpegData(compressionQuality: 0.7) }
            let newMemo = PageMemo(startPage: startPage, endPage: endPageInt, memo: trimmedMemo, book: book, imageData: memoImageData)
            
            book.memos = (book.memos ?? []) + [newMemo]
            modelContext.insert(newMemo)
        }
        
        // ⭐️ 표지 업데이트
        if let image = tempImage {
            if let data = resizeImage(image, targetWidth: 800).jpegData(compressionQuality: 0.7) { book.coverImageData = data }
        }
        
        do {
            try modelContext.save()
            if currentLoanStatus == .returned {
                removeReturnedLoanReminders()
            } else if updateLibraryLoan {
                updateLibraryLoanDates()
            }
        } catch {}
        
        dismiss(); onSave()
    }
    
    private func updateLibraryLoanDates() {
        let oldDueDate = book.dueDate
        book.updateInfo(checkoutDate: newCheckoutDate, dueDate: newDueDate)
        book.loanStatus = .borrowed
        try? modelContext.save()
        LoanCalendarManager.shared.updateLoanEvents(
            bookID: book.id.uuidString, title: book.title, author: book.author,
            checkoutDate: book.checkoutDate, dueDate: book.dueDate
        )
        if let oldDueDate, !Calendar.current.isDate(oldDueDate, inSameDayAs: newDueDate) {
            refreshDueReminderGroup(for: oldDueDate)
        }
        refreshDueReminderGroup(for: newDueDate)
        WatchSyncManager.shared.sendBooksToWatch([TimerStateManager.BookData.from(book)])
    }

    private func refreshDueReminderGroup(for dueDate: Date) {
        let dateKey = dateKeyFormatter.string(from: dueDate)
        WatchDueReminderScheduler.cancelGroup(dateKey: dateKey)
        WatchSyncManager.shared.cancelDueReminderGroupOnWatch(dateKey: dateKey)
        let titles = fetchBooks(dueDate: dueDate).map(\.title)
        guard !titles.isEmpty else { return }
        let payload = WatchDueReminderScheduler.DueGroupPayload(dateKey: dateKey, dueDate: dueDate, bookTitles: titles)
        Task {
            await WatchDueReminderScheduler.scheduleGroup(payload)
            WatchSyncManager.shared.sendDueReminderGroupToWatch(payload)
        }
    }

    private func removeReturnedLoanReminders() {
        LoanCalendarManager.shared.removeLoanEvents(forBookID: book.id.uuidString)
        guard let dueDate = book.dueDate else { return }
        let dateKey = dateKeyFormatter.string(from: dueDate)
        WatchDueReminderScheduler.cancelGroup(dateKey: dateKey)
        WatchSyncManager.shared.cancelDueReminderGroupOnWatch(dateKey: dateKey)

        let remainingTitles = fetchBooks(dueDate: dueDate).map(\.title)
        guard !remainingTitles.isEmpty else { return }
        let payload = WatchDueReminderScheduler.DueGroupPayload(
            dateKey: dateKey,
            dueDate: dueDate,
            bookTitles: remainingTitles
        )
        Task {
            await WatchDueReminderScheduler.scheduleGroup(payload)
            WatchSyncManager.shared.sendDueReminderGroupToWatch(payload)
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
    private var dateKeyFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
