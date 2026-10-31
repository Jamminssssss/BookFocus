// BookFocus Watch Watch App/WatchSessionManager.swift
import Foundation
import WatchConnectivity
import Combine

final class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {

    static let shared = WatchSessionManager()
    
    @Published private(set) var isSessionActivated = false
    @Published private(set) var isReachable = false
    
    // ✅ [수정] WCSession '활성화'가 되기 아주 짧은 찰나에 요청된 메시지만 담아두는 임시 보관소
    private var preActivationQueue: [[String: Any]] = []
    private let queueLock = NSLock()
    private let pendingSessionsKey = "watch.pendingSessionPayloads"
    
    // ❌ [치명적 오류 수정] 배터리를 광탈시키고 앱을 강제 종료시키던 5초 무한 재시도 타이머(retryTimer) 삭제 완료

    private override init() {
        super.init()
        activate()
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
    
    // MARK: - Send Message (안전한 전송 및 폴백 로직)
    
    /// 메시지 전송 (연결 시 즉시 전송, 실패 시 OS 백그라운드 큐로 안전하게 위임)
    func sendMessage(_ message: [String: Any]) {
        let session = WCSession.default
        
        // 1. 아직 세션이 활성화되지 않았다면 찰나의 순간이므로 임시 큐에 보관
        guard session.activationState == .activated else {
            queueLock.lock()
            preActivationQueue.append(message)
            queueLock.unlock()
            print("⏳ Session starting up, queued message temporarily")
            return
        }
        
        // 2. 활성화 상태라면 전송 시도
        sendOrTransfer(message)
    }

    /// Completed reading sessions are also kept on disk until WatchConnectivity
    /// confirms that its background transfer has finished.
    func sendSession(_ message: [String: Any]) {
        var queuedMessage = message
        queuedMessage["deliveryID"] = UUID().uuidString

        var pending = loadPendingSessions()
        pending.append(queuedMessage)
        savePendingSessions(pending)

        guard WCSession.default.activationState == .activated else { return }
        sendOrTransfer(queuedMessage)
    }
    
    // ✅ [수정] WCSession 강제 백그라운드 전송 보장 로직
    private func sendOrTransfer(_ message: [String: Any]) {
        let session = WCSession.default
        
        // 1. 앱이 꺼지거나 즉시 일시정지되더라도 OS가 나중에 무조건 전송하도록 보장 (핵심)
        session.transferUserInfo(message)
        print("📦 Queued to OS background transfer (transferUserInfo)")
        
        // 2. 아이폰 화면이 켜져 있는 경우, 즉시 화면에 반영되도록 sendMessage 병행 시도
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
            print("📡 Attempting immediate sendMessage")
        }
    }
    
    // 세션 활성화 직후에만 한 번 불리는 임시 큐 비우기
    private func flushPreActivationQueue() {
        queueLock.lock()
        let messages = preActivationQueue
        preActivationQueue.removeAll()
        queueLock.unlock()
        
        for message in messages {
            sendOrTransfer(message)
        }
    }

    private func flushPendingSessionOutbox() {
        for message in loadPendingSessions() {
            sendOrTransfer(message)
        }
    }

    private func loadPendingSessions() -> [[String: Any]] {
        UserDefaults(suiteName: AppGroupKey.suiteName)?
            .array(forKey: pendingSessionsKey) as? [[String: Any]] ?? []
    }

    private func savePendingSessions(_ messages: [[String: Any]]) {
        let defaults = UserDefaults(suiteName: AppGroupKey.suiteName)
        if messages.isEmpty {
            defaults?.removeObject(forKey: pendingSessionsKey)
        } else {
            defaults?.set(messages, forKey: pendingSessionsKey)
        }
    }

    private func removePendingSession(deliveryID: String) {
        var pending = loadPendingSessions()
        pending.removeAll { $0["deliveryID"] as? String == deliveryID }
        savePendingSessions(pending)
    }

    // MARK: - Message Handling

    private func handleMessage(_ payload: [String: Any]) {
        if let type = payload["type"] as? String {
            switch type {
            case "dueReminderGroup":
                handleDueReminderGroup(payload)
            case "cancelDueReminderGroup":
                handleCancelDueReminderGroup(payload)
            case "booksSync":
                handleBooks(payload)
            case "timerSync", "timerStateChanged":
                handleTimerSync(payload)
            default:
                print("⚠️ Unknown message type: \(type)")
            }
            return
        }
        
        handleBooks(payload)
    }

    private func handleBooks(_ payload: [String: Any]) {
        guard let data = payload["books"] as? Data,
              let receivedBooks = try? JSONDecoder().decode([TimerStateManager.BookData].self, from: data)
        else {
            print("❌ Watch failed to decode books")
            return
        }

        print("📥 Received \(receivedBooks.count) books from iPhone")
        let isFullSnapshot = payload["isFullSnapshot"] as? Bool ?? false
        let localBooks = TimerStateManager.shared.loadBooks()
        let mergedBooks = BookSyncLogic.merge(
            local: localBooks,
            incoming: receivedBooks,
            isFullSnapshot: isFullSnapshot
        )
        TimerStateManager.shared.saveBooks(mergedBooks)
        print("📚 \(isFullSnapshot ? "Full" : "Incremental") sync saved: \(mergedBooks.count) books")
    }
    
    private func handleDueReminderGroup(_ payload: [String: Any]) {
        guard let payloadData = payload["payload"] as? Data else { return }
        
        do {
            let groupPayload = try JSONDecoder().decode(WatchDueReminderScheduler.DueGroupPayload.self, from: payloadData)
            Task { await WatchDueReminderScheduler.scheduleGroup(groupPayload) }
            print("⌚️🔔 Scheduled group reminder")
        } catch {
            print("❌ Failed to decode due reminder group")
        }
    }
    
    private func handleCancelDueReminderGroup(_ payload: [String: Any]) {
        guard let dateKey = payload["dateKey"] as? String else { return }
        WatchDueReminderScheduler.cancelGroup(dateKey: dateKey)
    }

    private func handleTimerSync(_ payload: [String: Any]) {
        guard let bookID = payload["bookID"] as? String else { return }

        if let data = payload["state"] as? Data,
           let state = try? JSONDecoder().decode(SharedTimerState.self, from: data) {
            Task { @MainActor in TimerViewModel.shared.applyRemoteTimerState(state) }
            return
        }

        let action = payload["action"] as? String
        let isRunning = payload["isRunning"] as? Bool ?? (action == "start")
        let elapsedTime = payload["elapsedTime"] as? TimeInterval ?? 0

        Task { @MainActor in
            TimerViewModel.shared.applyRemoteTimerState(
                bookID: bookID,
                action: action,
                isRunning: isRunning,
                elapsedTime: elapsedTime
            )
        }
    }

    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isSessionActivated = (activationState == .activated)
            self.isReachable = session.isReachable
            
            if let error = error {
                print("❌ Session activation error:", error.localizedDescription)
            } else if activationState == .activated {
                print("✅ Session activated successfully")
                // ✅ 세션이 켜지자마자 대기 중이던 메시지 일괄 처리
                self.flushPreActivationQueue()
                self.flushPendingSessionOutbox()
                self.sendOrTransfer(["type": "requestTimerState"])
                self.sendOrTransfer(["type": "requestBooks"])
            }
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            print("⌚️ Reachability changed: \(session.isReachable)")
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        print("📥 Received userInfo from iOS")
        DispatchQueue.main.async { self.handleMessage(userInfo) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("📥 Received immediate message from iOS")
        DispatchQueue.main.async { self.handleMessage(message) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async { self.handleMessage(applicationContext) }
    }
    
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if let error = error {
            print("❌ UserInfo transfer failed: \(error.localizedDescription)")
        } else {
            if let deliveryID = userInfoTransfer.userInfo["deliveryID"] as? String {
                removePendingSession(deliveryID: deliveryID)
            }
            print("✅ OS completed background transfer successfully")
        }
    }
}
