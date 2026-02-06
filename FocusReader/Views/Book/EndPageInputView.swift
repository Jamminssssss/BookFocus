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
                                } else if let data = book.coverImageData,
                                          let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 150)
                                        .cornerRadius(8)
                                } else {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: 150)
                                        .cornerRadius(8)
                                        .overlay(Text("No Image").foregroundColor(.gray))
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
           
           if !memo.isEmpty && !storeManager.isPremium {
               errorMessage = "Premium is required to save memos."
               showError = true
               return
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
           
           dismiss()
           onSave()
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
    
    // MARK: - Watch Sync
    private func syncBookToWatch(_ book: Book) {
        let manager = TimerStateManager.shared
        let bookData = TimerStateManager.BookData(
            id: book.id.uuidString,
            title: book.title,
            author: book.author,
            totalPages: book.totalPages,
            currentPage: book.currentPage,
            createdAt: book.createdAt,
            lastUpdated: book.lastUpdated
        )
        manager.updateBook(bookData)
    }
}

