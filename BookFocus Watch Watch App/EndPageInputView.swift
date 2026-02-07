// BookFocus Watch Watch App/EndPageInputView.swift
import SwiftUI
import WatchConnectivity

struct EndPageInputView: View {
    let book: TimerStateManager.BookData
    let elapsedTime: TimeInterval
    var onSave: ((TimerStateManager.BookData) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var endPage: Int
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    private var startPage: Int { book.currentPage }

    init(book: TimerStateManager.BookData, elapsedTime: TimeInterval, onSave: ((TimerStateManager.BookData) -> Void)? = nil) {
        self.book = book
        self.elapsedTime = elapsedTime
        self.onSave = onSave
        _endPage = State(initialValue: book.currentPage)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {

                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                Text("마지막 페이지")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 14) {
                    Button {
                        endPage = max(startPage, endPage - 1)
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)

                    Text("\(endPage)")
                        .font(.system(size: 30, weight: .bold))
                        .frame(minWidth: 44)

                    Button {
                        endPage = min(book.totalPages, endPage + 1)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .safeAreaInset(edge: .bottom) {
                Button {
                    saveSession()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(isSaving ? "저장 중..." : "저장")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .padding(.horizontal)
                .padding(.bottom, 4)
                .disabled(isSaving)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(isSaving)
                }
            }
            .alert("오류", isPresented: $showError) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func saveSession() {
        guard endPage >= startPage else {
            errorMessage = "마지막 페이지는 시작 페이지보다 작을 수 없습니다."
            showError = true
            return
        }
        
        guard !isSaving else {
            print("⚠️ Already saving, ignoring duplicate save request")
            return
        }
        
        isSaving = true
        print("🔄 Starting save process...")

        // ✅ 1단계: 로컬 상태 업데이트
        let manager = TimerStateManager.shared
        var updatedBook = book
        updatedBook.currentPage = endPage
        updatedBook.lastUpdated = Date()
        
        print("📝 Updating book: \(updatedBook.title), page: \(endPage)")
        manager.updateBook(updatedBook)

        // ✅ 2단계: 세션 데이터 생성
        let startTime = Date().addingTimeInterval(-elapsedTime)
        let sessionData: [String: Any] = [
            "bookID": book.id,
            "startPage": startPage,
            "endPage": endPage,
            "duration": elapsedTime,
            "startTime": startTime.timeIntervalSince1970,
            "endTime": Date().timeIntervalSince1970
        ]
        
        print("📊 Session data created: \(startPage) → \(endPage), duration: \(elapsedTime)s")

        // ✅ 3단계: AppGroup 저장 (폴백 - 항상 실행)
        saveToAppGroup(sessionData: sessionData)

        // ✅ 4단계: iPhone 전송 (비동기)
        sendSessionToApp(sessionData: sessionData, updatedBook: updatedBook)

        // ✅ 5단계: 콜백 및 정리
        onSave?(updatedBook)
        manager.clearState()
        
        print("✅ Save process completed")
        
        // ✅ 딜레이를 늘려서 전송이 완료될 시간 확보
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isSaving = false
            dismiss()
        }
    }
    
    // ✅ AppGroup 저장 (폴백 메커니즘 - 개선)
    private func saveToAppGroup(sessionData: [String: Any]) {
        guard let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader") else {
            print("❌ Failed to access AppGroup")
            return
        }
        
        var sessions = defaults.array(forKey: "sessions.data") as? [[String: Any]] ?? []
        sessions.append(sessionData)
        defaults.set(sessions, forKey: "sessions.data")
        
        // ✅ 즉시 동기화
        let synced = defaults.synchronize()
        print("💾 Session saved to AppGroup (fallback): \(synced ? "SUCCESS" : "FAILED")")
        
        // ✅ 저장 확인
        if let savedSessions = defaults.array(forKey: "sessions.data") as? [[String: Any]] {
            print("✅ AppGroup now has \(savedSessions.count) session(s)")
        }
    }

    // ✅ 개선된 전송 메서드
    private func sendSessionToApp(sessionData: [String: Any], updatedBook: TimerStateManager.BookData) {
        guard
            let sessionJSON = try? JSONSerialization.data(withJSONObject: sessionData),
            let bookJSON = try? JSONEncoder().encode(updatedBook)
        else {
            print("❌ Failed to encode session or book data")
            return
        }

        let payload: [String: Any] = [
            "type": "sessionSaved",
            "session": sessionJSON,
            "book": bookJSON
        ]

        print("📤 Attempting to send session to app...")
        
        // ✅ WCSession 상태 확인
        let session = WCSession.default
        print("📡 WCSession state - Activated: \(session.activationState.rawValue), Reachable: \(session.isReachable)")
        
        // ✅ WatchSessionManager를 통해 전송 (재시도 로직 포함)
        WatchSessionManager.shared.sendMessage(payload)
        print("📤 Session sent to app via WatchSessionManager")
    }
}
