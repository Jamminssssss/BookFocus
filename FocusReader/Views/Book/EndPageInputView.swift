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
        
        let calendar = Calendar.current
        let today = Date()
        let startOfDay = calendar.startOfDay(for: today)
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
        
        // 새 이벤트 생성
        let bookHash = abs(book.id.uuidString.hashValue)
        let hourOffset = bookHash % 12
        let minuteOffset = (bookHash / 12) % 60
        let eventStartTime = calendar.date(byAdding: .hour, value: hourOffset, to: startOfDay)!
        let eventStartTimeWithMinutes = calendar.date(byAdding: .minute, value: minuteOffset, to: eventStartTime)!
        let eventEndTime = calendar.date(byAdding: .hour, value: 1, to: eventStartTimeWithMinutes)!
        
        let event = EKEvent(eventStore: eventStore)
        event.title = bookIdentifier
        event.notes = "Pages: \(startPage) - \(endPage) (\(endPage - startPage) pages read)"
        event.startDate = eventStartTimeWithMinutes
        event.endDate = eventEndTime
        event.calendar = eventStore.defaultCalendarForNewEvents
        try? eventStore.save(event, span: .thisEvent)
    }
}
