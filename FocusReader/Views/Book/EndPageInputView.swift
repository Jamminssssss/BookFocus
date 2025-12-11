//
//  EndPageInputView.swift
//  FocusReader
//
//  Created by JeaminPark on 12/10/25.
//

import SwiftUI
import SwiftData
import EventKit

struct EndPageInputView: View {
    @Environment(\.modelContext) private var modelContext
    
    let book: Book
    let session: ReadingSession?
    let onComplete: () -> Void
    
    @State private var endPage: String = ""
    @State private var memo: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    private let eventStore = EKEventStore()
    
    private var startPage: Int {
        session?.startPage ?? book.currentPage
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Start Page: \(startPage)")
                    TextField("End Page", text: $endPage)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Page Input")
                } footer: {
                    Text("End page is required.")
                }
                
                Section {
                    Text(book.title)
                        .font(.headline)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Book Information")
                }
                
                Section {
                    TextEditor(text: $memo)
                        .frame(minHeight: 150)
                } header: {
                    Text("Memo")
                } footer: {
                    Text("Write your thoughts about pages \(startPage) - \(endPage.isEmpty ? "?" : endPage)")
                }
            }
            .navigationTitle("End Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onComplete()
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
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveSession() {
        guard let endPageInt = Int(endPage) else {
            errorMessage = "Please enter a valid page number."
            showError = true
            return
        }
        
        guard endPageInt >= book.currentPage else {
            errorMessage = "End page must be greater than or equal to start page."
            showError = true
            return
        }
        
        guard endPageInt <= book.totalPages else {
            errorMessage = "End page cannot exceed total pages."
            showError = true
            return
        }
        
        // 세션 종료 처리
        if let session = session {
            // endSession은 duration을 다시 계산하므로, 이미 계산된 duration이 있으면 유지
            _ = session.duration
            session.endSession(endPage: endPageInt)
            // endSession에서 계산한 duration이 더 정확하므로 그대로 사용
        }
        
        // 책의 현재 페이지 업데이트
        book.currentPage = endPageInt
        
        // 완독 체크
        book.checkCompletion()
        
        // 누적 읽기 시간 업데이트
        book.updateTotalReadingTime()
        
        // 메모 저장 (구독 제한 없음)
        if !memo.isEmpty {
            let newMemo = PageMemo(
                startPage: startPage,
                endPage: endPageInt,
                memo: memo,
                book: book
            )
            
            if book.memos == nil {
                book.memos = []
            }
            book.memos?.append(newMemo)
            modelContext.insert(newMemo)
        }
        
        // SwiftData 저장
        try? modelContext.save()
        
        // 캘린더에 이벤트 추가
        addToCalendar(startPage: startPage, endPage: endPageInt)
        
        onComplete()
    }
    
    private func addToCalendar(startPage: Int, endPage: Int) {
        // 캘린더 접근 권한 요청 (iOS 17+는 새로운 API 사용, 그 이전은 fallback)
        if #available(iOS 17.0, *) {
            eventStore.requestWriteOnlyAccessToEvents { granted, error in
                if granted && error == nil {
                    DispatchQueue.main.async {
                        self.createCalendarEvent(startPage: startPage, endPage: endPage)
                    }
                } else if let error {
                    print("Calendar access error: \(error)")
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in
                if granted && error == nil {
                    DispatchQueue.main.async {
                        self.createCalendarEvent(startPage: startPage, endPage: endPage)
                    }
                } else if let error {
                    print("Calendar access error: \(error)")
                }
            }
        }
    }
    
    private func createCalendarEvent(startPage: Int, endPage: Int) {
        guard session != nil else { return }
        
        // 오늘 날짜의 시작과 끝 시간 설정
        let calendar = Calendar.current
        let today = Date()
        let startOfDay = calendar.startOfDay(for: today)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        // 같은 날의 기존 이벤트 찾기
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let existingEvents = eventStore.events(matching: predicate)
        
        // 이 책의 고유 식별자 (제목 + 작가 조합으로 정확하게 식별)
        let bookIdentifier = "\(book.title) - \(book.author)"
        
        // 같은 책의 이벤트만 찾기 (제목과 작가가 모두 일치하는 이벤트)
        let bookEvents = existingEvents.filter { event in
            // 정확한 제목 매칭 또는 제목과 작가가 모두 포함된 경우
            if let title = event.title {
                return title == bookIdentifier || 
                       (title.contains(book.title) && title.contains(book.author))
            }
            return false
        }
        
        // 같은 책의 기존 이벤트만 삭제 (다른 책의 이벤트는 유지)
        for event in bookEvents {
            do {
                try eventStore.remove(event, span: .thisEvent)
            } catch {
                print("Failed to remove existing event: \(error)")
            }
        }
        
        // 책별로 고유한 시간대 할당 (책 ID를 사용하여 시간 오프셋 계산)
        // 각 책마다 0시부터 시작해서 1시간씩 간격을 두고 배치
        let bookHash = abs(book.id.uuidString.hashValue)
        let hourOffset = bookHash % 12 // 0-11시 사이에 배치 (12시간 범위)
        let minuteOffset = (bookHash / 12) % 60 // 분 단위로 더 세밀하게 분산
        
        // 이벤트 시작 시간 계산 (각 책마다 다른 시간대)
        let eventStartTime = calendar.date(byAdding: .hour, value: hourOffset, to: startOfDay)!
        let eventStartTimeWithMinutes = calendar.date(byAdding: .minute, value: minuteOffset, to: eventStartTime)!
        
        // 이벤트 종료 시간 (1시간 후)
        let eventEndTime = calendar.date(byAdding: .hour, value: 1, to: eventStartTimeWithMinutes)!
        
        // 읽은 페이지 수 계산
        let pagesRead = endPage - startPage
        
        // 새 이벤트 생성 (각 책별로 독립적인 이벤트, 다른 시간대에 배치)
        let event = EKEvent(eventStore: eventStore)
        event.title = bookIdentifier
        event.notes = "Pages: \(startPage) - \(endPage) (\(pagesRead) pages read)\nCurrent Progress: \(endPage) / \(book.totalPages) pages"
        event.startDate = eventStartTimeWithMinutes
        event.endDate = eventEndTime
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.isAllDay = false // 하루 종일 이벤트가 아닌 시간 지정 이벤트로 설정
        
        // 이벤트 저장
        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            print("Failed to save event to calendar: \(error)")
        }
    }
}

