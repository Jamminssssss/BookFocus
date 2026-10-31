//
//  LoanCalendarManager.swift
//  FocusReader
//

import Foundation
import EventKit

public final class LoanCalendarManager {
    public static let shared = LoanCalendarManager()
    private let eventStore = EKEventStore()
    
    private init() {}
    
    // MARK: - 권한 요청
    public func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }
    
    // MARK: - 대출/반납 일정 등록 및 덮어쓰기
    /// 대출일과 반납 예정일이 변경되거나 새로 지정될 때 호출합니다.
    public func updateLoanEvents(
        bookID: String,
        title: String,
        author: String,
        checkoutDate: Date?,
        dueDate: Date?
    ) {
        requestAccess { [weak self] granted in
            guard let self = self, granted else {
                print("❌ [LoanCalendarManager] 캘린더 접근 권한이 없습니다.")
                return
            }
            
            // 1. 덮어쓰기를 위해 기존에 등록된 해당 도서의 대출/반납 이벤트 삭제
            self.removeExistingEvents(forBookID: bookID)
            
            // 2. 대출일 이벤트 추가
            if let checkoutDate = checkoutDate {
                let checkoutTitleFormat = NSLocalizedString("calendar_checkout_title_format", comment: "Checkout event title format in calendar")
                let checkoutNotesFormat = NSLocalizedString("calendar_checkout_notes_format", comment: "Checkout event notes format in calendar")
                
                let eventTitle = String(format: checkoutTitleFormat, title)
                let eventNotes = String(format: checkoutNotesFormat, author)
                
                self.createEvent(
                    bookID: bookID,
                    title: eventTitle,
                    notes: eventNotes,
                    date: checkoutDate,
                    type: "checkout"
                )
            }
            
            // 3. 반납 예정일 이벤트 추가
            if let dueDate = dueDate {
                let dueTitleFormat = NSLocalizedString("calendar_due_title_format", comment: "Due date event title format in calendar")
                let dueNotesFormat = NSLocalizedString("calendar_due_notes_format", comment: "Due date event notes format in calendar")
                
                let eventTitle = String(format: dueTitleFormat, title)
                let eventNotes = String(format: dueNotesFormat, author)
                
                self.createEvent(
                    bookID: bookID,
                    title: eventTitle,
                    notes: eventNotes,
                    date: dueDate,
                    type: "due"
                )
            }
            
            print("📅 [LoanCalendarManager] 캘린더 대출/반납 예정일 갱신 완료 (\(title))")
        }
    }
    
    // MARK: - 기존 이벤트 삭제 (반납 완료 또는 삭제 시 호출)
    public func removeLoanEvents(forBookID bookID: String) {
        requestAccess { [weak self] granted in
            guard let self = self, granted else { return }
            self.removeExistingEvents(forBookID: bookID)
            print("🗑️ [LoanCalendarManager] 캘린더 이벤트 삭제 완료 (\(bookID))")
        }
    }
    
    // MARK: - Private Helpers
    private func createEvent(bookID: String, title: String, notes: String, date: Date, type: String) {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        // 💡 덮어쓰기 및 중복 검색을 위한 고유 URL 지정
        event.url = URL(string: "focusreader://loan/\(type)/\(bookID)")
        
        // 종일 이벤트(All-Day)로 설정하여 캘린더 상단에 깔끔하게 표시
        event.isAllDay = true
        let startOfDay = Calendar.current.startOfDay(for: date)
        event.startDate = startOfDay
        event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        
        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            print("❌ [LoanCalendarManager] 이벤트 저장 실패 (\(type)): \(error.localizedDescription)")
        }
    }
    
    private func removeExistingEvents(forBookID bookID: String) {
        let calendar = Calendar.current
        let now = Date()
        
        // 앞뒤 3년 범위 내에서 고유 식별자(URL)가 일치하는 이벤트 검색 후 삭제
        guard let startDate = calendar.date(byAdding: .year, value: -3, to: now),
              let endDate = calendar.date(byAdding: .year, value: 3, to: now) else { return }
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let existingEvents = eventStore.events(matching: predicate)
        
        let checkoutURL = URL(string: "focusreader://loan/checkout/\(bookID)")
        let dueURL = URL(string: "focusreader://loan/due/\(bookID)")
        
        for event in existingEvents {
            if event.url == checkoutURL || event.url == dueURL {
                do {
                    try eventStore.remove(event, span: .thisEvent)
                } catch {
                    print("❌ [LoanCalendarManager] 기존 이벤트 삭제 실패: \(error.localizedDescription)")
                }
            }
        }
    }
}
