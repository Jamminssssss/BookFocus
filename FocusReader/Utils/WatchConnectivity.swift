// FocusReader/Utils/WatchConnectivity.swift
// ✅ 수정됨: 워치에서 저장한 세션도 캘린더에 반영되도록 EventKit 추가

import Foundation
import WatchConnectivity
import SwiftData
import EventKit  // ⭐ EventKit import 추가

final class WatchSyncManager: NSObject, WCSessionDelegate {
    
    static let shared = WatchSyncManager()
    
    private let appGroupID = "group.com.Jaemin.FocusReader"
    
    // SwiftData ModelContext를 외부에서 설정
    var modelContext: ModelContext?
    
    // ⭐ EventStore 추가 (캘린더 이벤트 생성용)
    private let eventStore = EKEventStore()
    
    private override init() {
        super.init()
    }
    
    // 🔥 App에서 명시적으로 시작
    func start() {
        activate()
        sendCachedBooksIfNeeded()
        // AppGroup의 세션 데이터 확인
        processPendingSessions()
    }
    
    // MARK: - WCSession 활성화
    private func activate() {
        guard WCSession.isSupported() else {
            print("❌ WCSession not supported")
            return
        }
        
        let session = WCSession.default
        session.delegate = self
        session.activate()
        print("📱 WCSession activation initiated")
    }
    
    // MARK: - 📤 책 목록 전송
    func sendBooksToWatch(_ books: [TimerStateManager.BookData]) {
        
        // 1️⃣ AppGroup에 항상 저장 (워치 fallback)
        saveBooksToAppGroup(books)
        
        guard WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else {
            print("❌ Watch not paired or not installed")
            return
        }
        
        guard let data = try? JSONEncoder().encode(books) else {
            print("❌ Failed to encode books")
            return
        }
        
        let payload: [String: Any] = ["books": data]
        
        // 2️⃣ 도달 가능하면 즉시 전송
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { error in
                print("❌ sendMessage error:", error.localizedDescription)
            }
            print("📡 Sent books via sendMessage:", books.count)
        } else {
            // 3️⃣ 아니면 백그라운드 전송
            WCSession.default.transferUserInfo(payload)
            print("📦 Sent books via transferUserInfo:", books.count)
        }
    }
    
    // MARK: - 📤 반납일 그룹 알림 전송
    func sendDueReminderGroupToWatch(_ payload: WatchDueReminderScheduler.DueGroupPayload) {
        guard WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else {
            print("❌ Watch not paired or not installed")
            return
        }
        
        guard let payloadData = try? JSONEncoder().encode(payload) else {
            print("❌ Failed to encode due reminder group payload")
            return
        }
        
        let message: [String: Any] = [
            "type": "dueReminderGroup",
            "payload": payloadData
        ]
        
        // 도달 가능하면 즉시 전송
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("❌ sendMessage error (dueReminderGroup):", error.localizedDescription)
            }
            print("📡 Sent due reminder group via sendMessage:", payload.dateKey)
        } else {
            // 백그라운드 전송
            WCSession.default.transferUserInfo(message)
            print("📦 Sent due reminder group via transferUserInfo:", payload.dateKey)
        }
    }
    
    // MARK: - 📤 반납일 그룹 알림 취소
    func cancelDueReminderGroupOnWatch(dateKey: String) {
        guard WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else {
            print("❌ Watch not paired or not installed")
            return
        }
        
        let message: [String: Any] = [
            "type": "cancelDueReminderGroup",
            "dateKey": dateKey
        ]
        
        // 도달 가능하면 즉시 전송
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("❌ sendMessage error (cancelDueReminderGroup):", error.localizedDescription)
            }
            print("📡 Sent cancel due reminder group via sendMessage:", dateKey)
        } else {
            // 백그라운드 전송
            WCSession.default.transferUserInfo(message)
            print("📦 Sent cancel due reminder group via transferUserInfo:", dateKey)
        }
    }
    
    // MARK: - AppGroup 저장 (Fallback)
    private func saveBooksToAppGroup(_ books: [TimerStateManager.BookData]) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(books) else { return }
        
        defaults.set(data, forKey: "books.data")
        defaults.synchronize()
        
        print("💾 Books saved to AppGroup:", books.count)
    }
    
    // MARK: - 이전 데이터 재전송
    private func sendCachedBooksIfNeeded() {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: "books.data"),
              let books = try? JSONDecoder().decode([TimerStateManager.BookData].self, from: data)
        else { return }
        
        sendBooksToWatch(books)
    }
    
    // MARK: - 📥 Watch → iOS 메시지 처리
    func handleWatchMessage(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else {
            print("⚠️ Watch: Received message without type")
            return
        }
        
        if type == "sessionSaved" {
            handleSessionSaved(payload)
        } else if type == "bookUpdated" {
            handleBookUpdated(payload)
        }
    }
    
    // MARK: - 세션 저장 처리
    private func handleSessionSaved(_ payload: [String: Any]) {
        guard let sessionData = payload["session"] as? Data,
              let bookData = payload["book"] as? Data,
              let sessionDict = try? JSONSerialization.jsonObject(with: sessionData) as? [String: Any],
              let updatedBook = try? JSONDecoder().decode(TimerStateManager.BookData.self, from: bookData),
              let modelContext = modelContext else {
            print("❌ Watch: Failed to decode session or book data")
            return
        }
        
        saveSessionToSwiftData(sessionDict: sessionDict, updatedBook: updatedBook, modelContext: modelContext)
    }
    
    // MARK: - 책 업데이트 처리
    private func handleBookUpdated(_ payload: [String: Any]) {
        guard let bookData = payload["book"] as? Data,
              let updatedBook = try? JSONDecoder().decode(TimerStateManager.BookData.self, from: bookData),
              let modelContext = modelContext else {
            print("❌ Watch: Failed to decode book data")
            return
        }
        
        updateBookInSwiftData(updatedBook: updatedBook, modelContext: modelContext)
    }
    
    // MARK: - SwiftData에 세션 저장 (⭐ 캘린더 이벤트 추가)
    private func saveSessionToSwiftData(
        sessionDict: [String: Any],
        updatedBook: TimerStateManager.BookData,
        modelContext: ModelContext
    ) {
        guard let bookIDString = sessionDict["bookID"] as? String,
              let bookID = UUID(uuidString: bookIDString),
              let startPage = sessionDict["startPage"] as? Int,
              let endPage = sessionDict["endPage"] as? Int,
              let duration = sessionDict["duration"] as? TimeInterval,
              let startTimeInterval = sessionDict["startTime"] as? TimeInterval else {
            print("❌ Watch: Invalid session data")
            return
        }
        
        // 책 찾기
        let fetchDescriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.id == bookID }
        )
        
        guard let book = try? modelContext.fetch(fetchDescriptor).first else {
            print("❌ Watch: Book not found: \(bookIDString)")
            return
        }
        
        // 세션 생성
        let startTime = Date(timeIntervalSince1970: startTimeInterval)
        let session = ReadingSession(startTime: startTime, startPage: startPage)
        session.endSession(endPage: endPage)
        session.duration = duration
        
        // 책에 세션 추가
        book.addSession(session)
        modelContext.insert(session)
        
        // 책 정보 업데이트
        book.currentPage = updatedBook.currentPage
        book.lastUpdated = updatedBook.lastUpdated
        book.checkCompletion()
        
        // ⭐ 캘린더 이벤트 생성 (워치에서 온 세션도 캘린더에 추가)
        addToCalendar(book: book, session: session, startPage: startPage, endPage: endPage)
        
        // 저장
        do {
            try modelContext.save()
            print("✅ Watch: Session saved to SwiftData - Book: \(book.title), Pages: \(startPage)-\(endPage), Duration: \(duration)s")
            print("📅 Watch: Calendar event created for session")
        } catch {
            print("❌ Watch: Failed to save session: \(error)")
        }
    }
    
    // MARK: - SwiftData에서 책 업데이트
    private func updateBookInSwiftData(
        updatedBook: TimerStateManager.BookData,
        modelContext: ModelContext
    ) {
        guard let bookID = UUID(uuidString: updatedBook.id) else {
            print("❌ Watch: Invalid book ID: \(updatedBook.id)")
            return
        }
        
        let fetchDescriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.id == bookID }
        )
        
        guard let book = try? modelContext.fetch(fetchDescriptor).first else {
            print("❌ Watch: Book not found: \(updatedBook.id)")
            return
        }
        
        // 책 정보 업데이트
        book.currentPage = updatedBook.currentPage
        book.lastUpdated = updatedBook.lastUpdated
        book.checkCompletion()
        
        // 저장
        do {
            try modelContext.save()
            print("✅ Watch: Book updated in SwiftData - \(book.title), Page: \(updatedBook.currentPage)")
        } catch {
            print("❌ Watch: Failed to update book: \(error)")
        }
    }
    
    // MARK: - AppGroup의 대기 중인 세션 처리 (⭐ 캘린더 이벤트 추가)
    func processPendingSessions() {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let sessions = defaults.array(forKey: "sessions.data") as? [[String: Any]],
              !sessions.isEmpty,
              let modelContext = modelContext else {
            return
        }
        
        print("📦 Processing \(sessions.count) pending sessions from AppGroup")
        
        var processedCount = 0
        
        for sessionDict in sessions {
            guard let bookIDString = sessionDict["bookID"] as? String,
                  let bookID = UUID(uuidString: bookIDString) else {
                print("⚠️ Invalid session data, skipping")
                continue
            }
            
            // 책 찾기
            let fetchDescriptor = FetchDescriptor<Book>(
                predicate: #Predicate<Book> { $0.id == bookID }
            )
            
            guard let book = try? modelContext.fetch(fetchDescriptor).first,
                  let startPage = sessionDict["startPage"] as? Int,
                  let endPage = sessionDict["endPage"] as? Int,
                  let duration = sessionDict["duration"] as? TimeInterval,
                  let startTimeInterval = sessionDict["startTime"] as? TimeInterval else {
                print("⚠️ Book not found or invalid session data for ID: \(bookIDString)")
                continue
            }
            
            print("📝 Processing session for book: \(book.title), pages: \(startPage)-\(endPage)")
            
            // 세션 생성
            let startTime = Date(timeIntervalSince1970: startTimeInterval)
            let session = ReadingSession(startTime: startTime, startPage: startPage)
            session.endSession(endPage: endPage)
            session.duration = duration
            
            // 책에 세션 추가
            book.addSession(session)
            book.currentPage = endPage
            book.checkCompletion()
            modelContext.insert(session)
            
            // ⭐ 캘린더 이벤트 생성 추가
            addToCalendar(book: book, session: session, startPage: startPage, endPage: endPage)
            
            processedCount += 1
        }
        
        // 저장
        if processedCount > 0 {
            do {
                try modelContext.save()
                defaults.removeObject(forKey: "sessions.data")
                defaults.synchronize()
                print("✅ Successfully processed and saved \(processedCount)/\(sessions.count) sessions from AppGroup")
                print("📅 Calendar events created for \(processedCount) sessions")
            } catch {
                print("❌ Failed to save pending sessions: \(error)")
            }
        } else {
            print("⚠️ No valid sessions to process")
        }
    }
    
    // MARK: - ⭐ 캘린더 이벤트 생성
    
    private func addToCalendar(book: Book, session: ReadingSession, startPage: Int, endPage: Int) {
        if #available(iOS 17.0, *) {
            eventStore.requestWriteOnlyAccessToEvents { [weak self] granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        self?.createCalendarEvent(book: book, session: session, startPage: startPage, endPage: endPage)
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, _ in
                if granted {
                    DispatchQueue.main.async {
                        self?.createCalendarEvent(book: book, session: session, startPage: startPage, endPage: endPage)
                    }
                }
            }
        }
    }
    
    private func createCalendarEvent(book: Book, session: ReadingSession, startPage: Int, endPage: Int) {
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
        
        // 세션 시작 시간 사용
        let eventStartTime = session.startTime
        
        // 실제 세션 종료 시간 사용 (또는 1시간 후)
        let eventEndTime: Date
        if let endTime = session.endTime {
            eventEndTime = endTime
        } else {
            eventEndTime = calendar.date(byAdding: .hour, value: 1, to: eventStartTime) ?? eventStartTime.addingTimeInterval(3600)
        }
        
        // 이벤트 생성
        let event = EKEvent(eventStore: eventStore)
        event.title = bookIdentifier
        event.notes = "Pages: \(startPage) - \(endPage) (\(endPage - startPage) pages read)"
        event.startDate = eventStartTime
        event.endDate = eventEndTime
        event.timeZone = TimeZone.current
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        do {
            try eventStore.save(event, span: .thisEvent)
            print("✅ Calendar event created: \(bookIdentifier)")
        } catch {
            print("❌ Failed to create calendar event: \(error)")
        }
    }
    
    // MARK: - WCSessionDelegate (iOS 필수 메서드)
    
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            print("❌ WCSession activation error:", error.localizedDescription)
        } else {
            print("📱 WCSession activated:", activationState.rawValue)
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("📱 WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("📱 WCSession deactivated, reactivating...")
        WCSession.default.activate()
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("📱 WCSession reachability changed: \(session.isReachable)")
    }
    
    // 📥 Watch → iOS (백그라운드)
    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String : Any]
    ) {
        print("📥 Received userInfo from Watch")
        handleWatchMessage(userInfo)
    }
    
    // 📥 Watch → iOS (즉시)
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String : Any]
    ) {
        print("📥 Received message from Watch")
        handleWatchMessage(message)
    }
}
