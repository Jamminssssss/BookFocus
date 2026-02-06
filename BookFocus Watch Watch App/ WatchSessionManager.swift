import Foundation
import WatchConnectivity

final class WatchSessionManager: NSObject, WCSessionDelegate {

    static let shared = WatchSessionManager()

    private override init() {
        super.init()
        activate()
    }

    private func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        print("⌚️ WCSession activated (Watch)")
    }

    // 📥 iOS → Watch (백그라운드)
    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String : Any]
    ) {
        handleMessage(userInfo)
    }

    // 📥 iOS → Watch (즉시)
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String : Any]
    ) {
        handleMessage(message)
    }

    // MARK: - 통합 메시지 처리
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

    private func handleBooks(_ payload: [String: Any]) {
        guard let data = payload["books"] as? Data,
              let books = try? JSONDecoder().decode(
                [TimerStateManager.BookData].self,
                from: data
              )
        else {
            print("❌ Watch failed to decode books")
            return
        }

        TimerStateManager.shared.saveBooks(books)
        print("📚 Watch received books:", books.count)
    }
    
    // MARK: - 반납일 그룹 알림 처리 (수정)
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
    
    // MARK: - 반납일 그룹 알림 취소 (수정)
    private func handleCancelDueReminderGroup(_ payload: [String: Any]) {
        guard let dateKey = payload["dateKey"] as? String else {
            print("❌ Missing dateKey")
            return
        }
        
        WatchDueReminderScheduler.cancelGroup(dateKey: dateKey)
        print("⌚️🔕 Cancelled group reminder for: \(dateKey)")
    }

    // Required
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        print("⌚️ Session state: \(activationState.rawValue)")
    }
}
