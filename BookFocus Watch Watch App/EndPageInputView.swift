//
//  EndPageInputView.swift
//  BookFocus Watch Watch App
//

import SwiftUI
import WatchConnectivity

struct EndPageInputView: View {
    let book: TimerStateManager.BookData
    let elapsedTime: TimeInterval

    @Environment(\.dismiss) private var dismiss

    @State private var endPage: String = ""
    @State private var showError = false
    @State private var errorMessage = ""

    private var startPage: Int {
        book.currentPage
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // 책 정보
                    VStack(spacing: 4) {
                        Text(book.title)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        Text("시작: \(startPage) 페이지")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)

                    // 경과 시간
                    Text(formatTime(elapsedTime))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)

                    // 페이지 입력 (watchOS 대응)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("마지막 페이지")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("페이지 입력", text: $endPage)
                            .textFieldStyle(.plain)
                    }

                    // 저장 버튼
                    Button("저장") {
                        saveSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(endPage.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("세션 종료")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
            }
            .alert("오류", isPresented: $showError) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Save

    private func saveSession() {
        let trimmed = endPage.trimmingCharacters(in: .whitespaces)

        guard let endPageInt = Int(trimmed) else {
            errorMessage = "올바른 페이지 번호를 입력하세요."
            showError = true
            return
        }

        guard endPageInt >= startPage else {
            errorMessage = "마지막 페이지는 시작 페이지보다 크거나 같아야 합니다."
            showError = true
            return
        }

        guard endPageInt <= book.totalPages else {
            errorMessage = "마지막 페이지는 총 페이지를 초과할 수 없습니다."
            showError = true
            return
        }

        let manager = TimerStateManager.shared

        // 책 정보 업데이트
        var updatedBook = book
        updatedBook.currentPage = endPageInt
        updatedBook.lastUpdated = Date()
        manager.updateBook(updatedBook)

        // 세션 정보 준비
        let startTime = Date().addingTimeInterval(-elapsedTime)
        let sessionData: [String: Any] = [
            "bookID": book.id,
            "startPage": startPage,
            "endPage": endPageInt,
            "duration": elapsedTime,
            "startTime": startTime.timeIntervalSince1970,
            "endTime": Date().timeIntervalSince1970
        ]

        // AppGroup에 세션 저장 (fallback)
        if let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader") {
            var sessions = defaults.array(forKey: "sessions.data") as? [[String: Any]] ?? []
            sessions.append(sessionData)
            defaults.set(sessions, forKey: "sessions.data")
            defaults.synchronize()
        }

        // WatchConnectivity로 앱에 세션 데이터 전송
        sendSessionToApp(sessionData: sessionData, updatedBook: updatedBook)

        // iOS 앱에 알림 (fallback)
        manager.setAction("sessionSaved")

        // 타이머 상태 초기화
        manager.clearState()

        dismiss()
    }
    
    // MARK: - Send Session to App
    private func sendSessionToApp(sessionData: [String: Any], updatedBook: TimerStateManager.BookData) {
        let session = WCSession.default
        
        // watchOS에서는 activationState와 isReachable만 체크
        guard session.activationState == .activated else {
            print("⚠️ Watch: WCSession not activated, using AppGroup fallback")
            return
        }
        
        // 세션 데이터 인코딩
        guard let sessionJSON = try? JSONSerialization.data(withJSONObject: sessionData),
              let bookJSON = try? JSONEncoder().encode(updatedBook) else {
            print("❌ Watch: Failed to encode session or book data")
            return
        }
        
        let payload: [String: Any] = [
            "type": "sessionSaved",
            "session": sessionJSON,
            "book": bookJSON
        ]
        
        // 즉시 전송 시도 (앱이 활성화된 경우)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { reply in
                print("✅ Watch: Session sent to app, reply: \(reply)")
            }) { error in
                print("❌ Watch: SendMessage error: \(error.localizedDescription)")
                // 실패 시 백그라운드 전송
                session.transferUserInfo(payload)
            }
        } else {
            // 백그라운드 전송 (앱이 백그라운드에 있거나 실행 중이지 않은 경우)
            session.transferUserInfo(payload)
            print("📦 Watch: Session queued for background transfer")
        }
    }

    // MARK: - Time Format

    private func formatTime(_ time: TimeInterval) -> String {
        let h = Int(time) / 3600
        let m = Int(time) / 60 % 60
        let s = Int(time) % 60

        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
