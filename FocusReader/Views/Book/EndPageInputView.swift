// FocusReader/Views/Book/EndPageInputView.swift
import SwiftUI
import SwiftData
import EventKit
import PhotosUI

struct EndPageInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let book: Book
    let session: ReadingSession?
    let onSave: () -> Void
    let onCancel: () -> Void
    
    // 🔑 StoreKit
    @StateObject private var storeManager = StoreKitManager.shared
    @State private var showPurchaseSheet = false
    
    @State private var endPage: String = ""
    @State private var memo: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    // 이미지
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var tempImage: UIImage?
    @State private var showCamera = false
    
    // 📚 도서관 대출 정보 변경
    @State private var updateLibraryLoan: Bool = false
    @State private var newCheckoutDate: Date = Date()
    @State private var newDueDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
    
    private let eventStore = EKEventStore()
    
    private var startPage: Int {
        session?.startPage ?? book.currentPage
    }
    
    // 🔒 메모 사용 가능 여부 (프리미엄만 허용)
    private var canUseMemo: Bool {
        storeManager.isPremium
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Top adaptive banner
                AdaptiveTopBannerView()

                NavigationStack {
                    Form {
                        // MARK: - Page Input
                        Section {
                            Text("Start Page: \(startPage)")
                            TextField("End Page", text: $endPage)
                                .keyboardType(.numberPad)
                        } header: {
                            Text("Page Input")
                        }
                        
                        // MARK: - Book Info
                        Section {
                            Text(book.title).font(.headline)
                            Text(book.author)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } header: {
                            Text("Book Information")
                        }
                        
                        // MARK: - 📚 도서관 대출일 변경
                        if book.hasDueDate {
                            Section {
                                Toggle("Update Library Loan Dates", isOn: $updateLibraryLoan)
                                
                                if updateLibraryLoan {
                                    VStack(alignment: .leading, spacing: 8) {
                                        // 현재 날짜 표시
                                        if let currentCheckout = book.checkoutDate,
                                           let currentDue = book.dueDate {
                                            HStack {
                                                Text("Current:")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                Text("\(currentCheckout, style: .date) → \(currentDue, style: .date)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.bottom, 4)
                                        }
                                        
                                        DatePicker(
                                            "New Checkout Date",
                                            selection: $newCheckoutDate,
                                            displayedComponents: .date
                                        )
                                        
                                        DatePicker(
                                            "New Due Date",
                                            selection: $newDueDate,
                                            in: newCheckoutDate...,
                                            displayedComponents: .date
                                        )
                                    }
                                }
                            } header: {
                                Text("Library Loan")
                            } footer: {
                                if updateLibraryLoan {
                                    Text("The previous due date reminder will be replaced with the new dates.")
                                }
                            }
                        }
                        
                        // MARK: - Memo (Premium Locked)
                        Section {
                            ZStack {
                                TextEditor(text: $memo)
                                    .frame(minHeight: 150)
                                    .disabled(!canUseMemo)
                                    .opacity(canUseMemo ? 1.0 : 0.2)
                                
                                if !canUseMemo {
                                    VStack(spacing: 12) {
                                        Image(systemName: "lock.fill")
                                            .font(.title)
                                            .foregroundColor(.secondary)
                                        
                                        Text("Premium Feature")
                                            .font(.headline)
                                        
                                        Text("Buy Premium to write memos permanently")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Button {
                                            showPurchaseSheet = true
                                        } label: {
                                            Text("Unlock with Premium")
                                                .fontWeight(.semibold)
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.black.opacity(0.05))
                                }
                            }
                        } header: {
                            Text("Memo")
                        } footer: {
                            if !storeManager.isPremium {
                                Text("Memos are available with Premium purchase.")
                            }
                        }
                        
                        // MARK: - Book Cover
                        Section {
                            VStack {
                                if let uiImage = selectedImage {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 150)
                                        .cornerRadius(8)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                } else if let data = book.coverImageData,
                                          let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 150)
                                        .cornerRadius(8)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                } else {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: 150)
                                        .cornerRadius(8)
                                        .overlay(Text("No Image").foregroundColor(.gray))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                            
                            HStack {
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
                        } header: {
                            Text("Book Cover")
                        }
                    }
                    .navigationTitle("End Session")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                // 위젯/라이브 액티비티 정리
                                TimerStateManager.shared.clearState()
                                // 라이브 액티비티 종료 신호 (ReadingTimerView가 수신하여 처리할 수 있도록 Notification 사용)
                                NotificationCenter.default.post(name: Notification.Name("ReadingTimer.EndLiveActivity"), object: nil)

                                dismiss()
                                onCancel()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                saveSession()
                            }
                            .disabled(endPage.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .alert("Error", isPresented: $showError) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(errorMessage)
                    }
                    .sheet(isPresented: $showCamera) {
                        ImagePicker(image: $selectedImage, sourceType: .camera)
                            .ignoresSafeArea()
                    }
                    .sheet(isPresented: $showPurchaseSheet) {
                        PurchaseView()
                    }
                    .onChange(of: selectedPhoto) { _, newValue in
                        Task {
                            if let data = try? await newValue?.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                selectedImage = image
                                tempImage = image
                            }
                        }
                    }
                    .onChange(of: selectedImage) { _, newValue in
                        if let image = newValue {
                            tempImage = image
                        }
                    }
                    .onAppear {
                        // 기존 대출일/반납일이 있으면 초기값으로 설정
                        if let checkout = book.checkoutDate {
                            newCheckoutDate = checkout
                        }
                        if let due = book.dueDate {
                            newDueDate = due
                        }
                    }
                    AdaptiveBottomBannerView()
                }
            }
        }
        .onDisappear {
            // 저장이 호출되지 않은 채로 사라질 수 있는 경우를 대비한 안전망
            // 세션 저장 플래그를 확인할 수 없으므로, 진행 중 세션의 위젯/라이브 액티비티를 정리
            TimerStateManager.shared.clearState()
            NotificationCenter.default.post(name: Notification.Name("ReadingTimer.EndLiveActivity"), object: nil)
        }
    }
    
    // MARK: - Save
    private func saveSession() {
        let trimmed = endPage.trimmingCharacters(in: .whitespaces)
        guard let endPageInt = Int(trimmed) else {
            errorMessage = "Please enter a valid page number."
            showError = true
            return
        }
        guard endPageInt >= startPage else {
            errorMessage = "End page must be greater than or equal to start page."
            showError = true
            return
        }
        guard endPageInt <= book.totalPages else {
            errorMessage = "End page cannot exceed total pages."
            showError = true
            return
        }
        
        // 날짜 유효성 검사
        if updateLibraryLoan && newCheckoutDate > newDueDate {
            errorMessage = "Due date must be after checkout date."
            showError = true
            return
        }
        
        if !memo.isEmpty && !storeManager.isPremium {
            errorMessage = "Premium is required to save memos."
            showError = true
            return
        }
        
        // 📚 도서관 대출일 업데이트 처리
        if updateLibraryLoan {
            updateLibraryLoanDates()
        }
        
        if let session = session {
            session.endSession(endPage: endPageInt)
        }
        
        book.currentPage = endPageInt
        book.checkCompletion()
        
        if !memo.isEmpty {
            let newMemo = PageMemo(
                startPage: startPage,
                endPage: endPageInt,
                memo: memo,
                book: book
            )
            var memos = book.memos ?? []
            memos.append(newMemo)
            book.memos = memos
            modelContext.insert(newMemo)
        }
        
        if let image = tempImage,
           let data = image.jpegData(compressionQuality: 0.8) {
            book.coverImageData = data
        }
        
        addToCalendar(startPage: startPage, endPage: endPageInt)
        
        
        // 모델 저장
        do {
            try modelContext.save()
            print("✅ Book updated and saved successfully")
        } catch {
            print("❌ Failed to save book: \(error)")
        }
        
        dismiss()
        onSave()
    }
    
    // MARK: - 📚 도서관 대출일 업데이트
    private func updateLibraryLoanDates() {
        print("🔄 Updating library loan dates...")
        
        // 1️⃣ 기존 알림 취소
        if let oldDueDate = book.dueDate {
            let oldDateKey = dateKeyFormatter.string(from: oldDueDate)
            
            // iOS 알림 취소
            WatchDueReminderScheduler.cancelGroup(dateKey: oldDateKey)
            
            // 워치 알림 취소
            WatchSyncManager.shared.cancelDueReminderGroupOnWatch(dateKey: oldDateKey)
            
            print("🔕 Cancelled old reminders for: \(oldDateKey)")
        }
        
        // 2️⃣ Book 모델 업데이트
        book.updateInfo(
            checkoutDate: newCheckoutDate,
            dueDate: newDueDate
        )
        
        print("📅 Updated dates - Checkout: \(newCheckoutDate), Due: \(newDueDate)")
        
        // 3️⃣ 새로운 알림 설정
        let newDateKey = dateKeyFormatter.string(from: newDueDate)
        
        // 같은 날짜의 다른 책들 가져오기
        let booksDueSameDay = fetchBooks(dueDate: newDueDate)
        
        // Payload 생성
        let payload = WatchDueReminderScheduler.DueGroupPayload(
            dateKey: newDateKey,
            dueDate: newDueDate,
            bookTitles: booksDueSameDay.map { $0.title }
        )
        
        Task {
            // iOS 앱 알림
            await WatchDueReminderScheduler.scheduleGroup(payload)
            
            // ⌚️ 워치 알림
            WatchSyncManager.shared.sendDueReminderGroupToWatch(payload)
            
            print("🔔 Scheduled new reminders for: \(newDateKey)")
        }
    }
    
    // MARK: - Fetch books with same due date
    private func fetchBooks(dueDate: Date) -> [Book] {
        do {
            let descriptor = FetchDescriptor<Book>(
                predicate: #Predicate { $0.dueDate == dueDate }
            )
            return try modelContext.fetch(descriptor)
        } catch {
            print("❌ Failed to fetch books for dueDate:", error)
            return []
        }
    }
    
    // MARK: - DateFormatter
    private var dateKeyFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }

    // MARK: - Calendar
    private func addToCalendar(startPage: Int, endPage: Int) {
        if #available(iOS 17.0, *) {
            eventStore.requestWriteOnlyAccessToEvents { granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        createCalendarEvent(startPage: startPage, endPage: endPage)
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        createCalendarEvent(startPage: startPage, endPage: endPage)
                    }
                }
            }
        }
    }
    
    private func createCalendarEvent(startPage: Int, endPage: Int) {
        guard session != nil else { return }
        
        // 현재 시간대를 사용하는 캘린더 설정
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // 중복 이벤트 제거
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let existingEvents = eventStore.events(matching: predicate)
        let bookIdentifier = "\(book.title) - \(book.author)"
        
        for event in existingEvents {
            if event.title == bookIdentifier {
                try? eventStore.remove(event, span: .thisEvent)
            }
        }
        
        // 세션 시작 시간 사용 (또는 현재 시간)
        let eventStartTime: Date
        if let sessionStartTime = session?.startTime {
            eventStartTime = sessionStartTime
        } else {
            eventStartTime = now
        }
        
        // 1시간 후를 종료 시간으로 설정
        let eventEndTime = calendar.date(byAdding: .hour, value: 1, to: eventStartTime) ?? eventStartTime.addingTimeInterval(3600)
        
        let event = EKEvent(eventStore: eventStore)
        event.title = bookIdentifier
        event.notes = "Pages: \(startPage) - \(endPage) (\(endPage - startPage) pages read)"
        event.startDate = eventStartTime
        event.endDate = eventEndTime
        event.timeZone = TimeZone.current
        event.calendar = eventStore.defaultCalendarForNewEvents
        try? eventStore.save(event, span: .thisEvent)
    }
    
}
