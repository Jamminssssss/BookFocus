import SwiftUI
import SwiftData
import EventKit
import PhotosUI

struct EndPageInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let book: Book
    let session: ReadingSession?
    let onSave: () -> Void  // ✅ Save 시 호출
    let onCancel: () -> Void  // ✅ Cancel 시 호출
    
    @State private var endPage: String = ""
    @State private var memo: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    // 이미지 관련 상태
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var tempImage: UIImage? // 임시 이미지
    @State private var showCamera = false
    
    private let eventStore = EKEventStore()
    
    private var startPage: Int {
        session?.startPage ?? book.currentPage
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Page Input
                Section {
                    Text("Start Page: \(startPage)")
                    TextField("End Page", text: $endPage)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Page Input")
                } footer: {
                    Text("End page is required.")
                }
                
                // MARK: - Book Information
                Section {
                    Text(book.title)
                        .font(.headline)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Book Information")
                }
                
                // MARK: - Memo
                Section {
                    TextEditor(text: $memo)
                        .frame(minHeight: 150)
                } header: {
                    Text("Memo")
                } footer: {
                    Text("Write your thoughts about pages \(startPage) - \(endPage.isEmpty ? "?" : endPage)")
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
                } header: {
                    Text("Book Cover")
                }
            }
            .navigationTitle("End Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // ✅ Cancel 시 아무것도 저장하지 않고 onCancel 호출
                        dismiss()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSession()
                    }
                    .disabled(endPage.isEmpty)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage) }
            .sheet(isPresented: $showCamera) {
                ImagePicker(image: $selectedImage, sourceType: .camera)
                    .ignoresSafeArea()
            }
            .onChange(of: selectedPhoto) { oldValue, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                        tempImage = image
                    }
                }
            }
            .onChange(of: selectedImage) { oldValue, newValue in
                if let image = newValue, oldValue != newValue {
                    tempImage = image
                }
            }
        }
    }
    
    // MARK: - Session Saving
    private func saveSession() {
        guard let endPageInt = Int(endPage) else {
            errorMessage = "Please enter a valid page number."
            showError = true
            return
        }
        guard endPageInt >= startPage else {
            errorMessage = "End page must be greater than or equal to start page (\(startPage))."
            showError = true
            return
        }
        guard endPageInt <= book.totalPages else {
            errorMessage = "End page cannot exceed total pages (\(book.totalPages))."
            showError = true
            return
        }
        
        // ✅ 세션 종료 처리 (endPage 설정)
        if let session = session {
            session.endSession(endPage: endPageInt)
        }
        
        // ✅ Book 정보 업데이트
        book.currentPage = endPageInt
        book.checkCompletion()
        
        // ✅ 메모 저장 (있는 경우에만)
        if !memo.isEmpty {
            let newMemo = PageMemo(startPage: startPage, endPage: endPageInt, memo: memo, book: book)
            var memos = book.memos ?? []
            memos.append(newMemo)
            book.memos = memos
            modelContext.insert(newMemo)
        }
        
        // ✅ 이미지 저장 (Save 버튼에서만)
        if let imageToSave = tempImage,
           let data = imageToSave.jpegData(compressionQuality: 0.8) {
            book.coverImageData = data
        }
        
        // ✅ 캘린더 이벤트 추가
        addToCalendar(startPage: startPage, endPage: endPageInt)
        
        // ✅ Save 완료 후 onSave 호출 (ReadingTimerView에서 SwiftData 저장 처리)
        dismiss()
        onSave()
    }
    
    // MARK: - Calendar Handling
    private func addToCalendar(startPage: Int, endPage: Int) {
        if #available(iOS 17.0, *) {
            eventStore.requestWriteOnlyAccessToEvents { granted, error in
                if granted && error == nil {
                    DispatchQueue.main.async {
                        self.createCalendarEvent(startPage: startPage, endPage: endPage)
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in
                if granted && error == nil {
                    DispatchQueue.main.async {
                        self.createCalendarEvent(startPage: startPage, endPage: endPage)
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
        
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let existingEvents = eventStore.events(matching: predicate)
        
        let bookIdentifier = "\(book.title) - \(book.author)"
        let bookEvents = existingEvents.filter { event in
            if let title = event.title {
                return title == bookIdentifier ||
                       (title.contains(book.title) && title.contains(book.author))
            }
            return false
        }
        
        for event in bookEvents {
            try? eventStore.remove(event, span: .thisEvent)
        }
        
        let bookHash = abs(book.id.uuidString.hashValue)
        let hourOffset = bookHash % 12
        let minuteOffset = (bookHash / 12) % 60
        
        let eventStartTime = calendar.date(byAdding: .hour, value: hourOffset, to: startOfDay)!
        let eventStartTimeWithMinutes = calendar.date(byAdding: .minute, value: minuteOffset, to: eventStartTime)!
        let eventEndTime = calendar.date(byAdding: .hour, value: 1, to: eventStartTimeWithMinutes)!
        let pagesRead = endPage - startPage
        
        let event = EKEvent(eventStore: eventStore)
        event.title = bookIdentifier
        event.notes = "Pages: \(startPage) - \(endPage) (\(pagesRead) pages read)\nCurrent Progress: \(endPage) / \(book.totalPages) pages"
        event.startDate = eventStartTimeWithMinutes
        event.endDate = eventEndTime
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.isAllDay = false
        try? eventStore.save(event, span: .thisEvent)
    }
}
