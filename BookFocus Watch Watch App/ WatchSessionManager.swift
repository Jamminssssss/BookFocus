// BookFocus Watch Watch App/WatchSessionManager.swift
import Foundation
import WatchConnectivity
import Combine

final class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {

    static let shared = WatchSessionManager()
    
    // ✅ 세션 활성화 상태 추적
    @Published private(set) var isSessionActivated = false
    @Published private(set) var isReachable = false
    
    // ✅ 대기 중인 메시지 큐
    private var pendingMessages: [[String: Any]] = []
    private let pendingMessagesLock = NSLock()
    
    // ✅ 재시도 타이머
    private var retryTimer: Timer?

    private override init() {
        super.init()
        activate()
        startPeriodicRetry()
    }

    private func activate() {
        guard WCSession.isSupported() else {
            print("❌ WCSession not supported")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        print("⌚️ WCSession activation initiated")
    }
    
    // ✅ 주기적으로 대기 중인 메시지 재시도
    private func startPeriodicRetry() {
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.processPendingMessages()
        }
    }
    
    deinit {
        retryTimer?.invalidate()
    }
    
    // MARK: - Send Message with Retry Logic
    
    /// 메시지 전송 (재시도 로직 포함)
    func sendMessage(_ message: [String: Any], maxRetries: Int = 3) {
        let session = WCSession.default
        
        print("📨 sendMessage called - Activated: \(isSessionActivated), Reachable: \(session.isReachable)")
        
        // 세션이 활성화되지 않았으면 대기 큐에 추가
        guard isSessionActivated else {
            print("⚠️ Session not activated yet, queuing message")
            queueMessage(message)
            return
        }
        
        // ✅ watchOS에서는 isPaired, isWatchAppInstalled 체크 불필요
        
        // 1순위: sendMessage (즉시 전송)
        if session.isReachable {
            session.sendMessage(message, replyHandler: { reply in
                print("✅ Message sent successfully with reply:", reply)
            }) { error in
                print("⚠️ sendMessage failed:", error.localizedDescription)
                // 실패 시 transferUserInfo로 폴백
                self.fallbackToTransferUserInfo(message)
            }
            print("📡 Sent message via sendMessage (reachable)")
        }
        // 2순위: transferUserInfo (백그라운드 전송)
        else {
            fallbackToTransferUserInfo(message)
        }
    }
    
    /// 메시지를 큐에 추가
    private func queueMessage(_ message: [String: Any]) {
        pendingMessagesLock.lock()
        pendingMessages.append(message)
        let count = pendingMessages.count
        pendingMessagesLock.unlock()
        print("📥 Message queued. Total pending: \(count)")
    }
    
    /// transferUserInfo로 폴백
    private func fallbackToTransferUserInfo(_ message: [String: Any]) {
        let session = WCSession.default
        let transfer = session.transferUserInfo(message)
        print("📦 Sent message via transferUserInfo (not reachable). Outstanding: \(session.outstandingUserInfoTransfers.count)")
        print("   Transfer file URL: \(transfer.userInfo)")
    }
    
    // MARK: - Process Pending Messages
    
    /// 대기 중인 메시지 모두 전송
    @objc private func processPendingMessages() {
        pendingMessagesLock.lock()
        let messages = pendingMessages
        pendingMessagesLock.unlock()
        
        guard !messages.isEmpty else { return }
        
        let session = WCSession.default
        
        // ✅ watchOS에서는 세션 활성화 상태만 체크
        guard isSessionActivated else {
            print("⏳ Cannot process pending messages yet. Waiting for session activation...")
            return
        }
        
        print("📬 Processing \(messages.count) pending messages")
        
        // 메시지를 하나씩 전송 시도
        var successCount = 0
        pendingMessagesLock.lock()
        var remainingMessages: [[String: Any]] = []
        
        for message in messages {
            if session.isReachable {
                session.sendMessage(message, replyHandler: { _ in
                    print("✅ Pending message sent successfully")
                }) { error in
                    print("⚠️ Pending message failed, will retry: \(error.localizedDescription)")
                    remainingMessages.append(message)
                }
                successCount += 1
            } else {
                // reachable하지 않으면 transferUserInfo 사용
                session.transferUserInfo(message)
                print("📦 Pending message sent via transferUserInfo")
                successCount += 1
            }
        }
        
        pendingMessages = remainingMessages
        pendingMessagesLock.unlock()
        
        if successCount > 0 {
            print("✅ Processed \(successCount) pending messages. Remaining: \(remainingMessages.count)")
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ payload: [String: Any]) {
        // 1️⃣ 타입 확인
        if let type = payload["type"] as? String {
            switch type {
            case "dueReminderGroup":
                handleDueReminderGroup(payload)
            case "cancelDueReminderGroup":
                handleCancelDueReminderGroup(payload)
            default:
                print("⚠️ Unknown message type: \(type)")
            }
            return
        }
        
        // 2️⃣ 책 목록 처리 (기존 로직)
        handleBooks(payload)
    }

    // ✨ 수정된 부분: 병합 로직 추가
    private func handleBooks(_ payload: [String: Any]) {
        guard let data = payload["books"] as? Data,
              let receivedBooks = try? JSONDecoder().decode(
                [TimerStateManager.BookData].self,
                from: data
              )
        else {
            print("❌ Watch failed to decode books")
            return
        }

        print("📥 Received \(receivedBooks.count) books from iPhone")
        
        // ✨ Watch의 로컬 데이터 로드
        let localBooks = TimerStateManager.shared.loadBooks()
        
        // ✨ 병합: 각 책의 최신 데이터 사용
        var mergedBooks: [TimerStateManager.BookData] = []
        
        for receivedBook in receivedBooks {
            if let localBook = localBooks.first(where: { $0.id == receivedBook.id }) {
                // 같은 책이 로컬에 있으면 lastUpdated 비교
                if localBook.lastUpdated > receivedBook.lastUpdated {
                    // Watch 데이터가 더 최신
                    mergedBooks.append(localBook)
                    print("  ✅ \(localBook.title): Using Watch data (page \(localBook.currentPage)) - newer than iPhone")
                } else {
                    // iPhone 데이터가 더 최신
                    mergedBooks.append(receivedBook)
                    print("  📱 \(receivedBook.title): Using iPhone data (page \(receivedBook.currentPage))")
                }
            } else {
                // 로컬에 없는 새 책
                mergedBooks.append(receivedBook)
                print("  🆕 \(receivedBook.title): New book from iPhone")
            }
        }
        
        // ✨ 병합된 데이터 저장
        TimerStateManager.shared.saveBooks(mergedBooks)
        print("📚 Merged books saved: \(mergedBooks.count) books")
    }
    
    // MARK: - 반납일 그룹 알림 처리
    private func handleDueReminderGroup(_ payload: [String: Any]) {
        guard let payloadData = payload["payload"] as? Data else {
            print("❌ Missing payload data")
            return
        }
        
        do {
            let groupPayload = try JSONDecoder().decode(
                WatchDueReminderScheduler.DueGroupPayload.self,
                from: payloadData
            )
            
            Task {
                await WatchDueReminderScheduler.scheduleGroup(groupPayload)
            }
            
            print("⌚️🔔 Scheduled group reminder for \(groupPayload.dateKey): \(groupPayload.bookTitles.count) books")
        } catch {
            print("❌ Failed to decode due reminder group: \(error)")
        }
    }
    
    private func handleCancelDueReminderGroup(_ payload: [String: Any]) {
        guard let dateKey = payload["dateKey"] as? String else {
            print("❌ Missing dateKey")
            return
        }
        
        WatchDueReminderScheduler.cancelGroup(dateKey: dateKey)
        print("⌚️🔕 Cancelled group reminder for: \(dateKey)")
    }

    // MARK: - WCSessionDelegate
    
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isSessionActivated = (activationState == .activated)
            self.isReachable = session.isReachable
            
            if let error = error {
                print("❌ Session activation error:", error.localizedDescription)
            } else {
                print("✅ Session activated: \(activationState.rawValue)")
                print("   Activation State: \(activationState.rawValue)")
                print("   Reachable: \(session.isReachable)")
                
                // ✅ 활성화 완료 후 대기 중인 메시지 전송
                if activationState == .activated {
                    // 약간의 딜레이 후 처리 (완전한 활성화 대기)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.processPendingMessages()
                    }
                }
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            print("⌚️ Reachability changed: \(session.isReachable)")
            
            // ✅ 연결 가능해지면 대기 중인 메시지 재전송
            if session.isReachable {
                self.processPendingMessages()
            }
        }
    }

    // 📥 iOS → Watch (백그라운드)
    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String : Any]
    ) {
        print("📥 Received userInfo from iOS")
        handleMessage(userInfo)
    }

    // 📥 iOS → Watch (즉시)
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String : Any]
    ) {
        print("📥 Received message from iOS")
        handleMessage(message)
    }
    
    // ✅ transferUserInfo 완료 콜백
    func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        if let error = error {
            print("❌ UserInfo transfer failed: \(error.localizedDescription)")
        } else {
            print("✅ UserInfo transfer completed successfully")
        }
    }
}
