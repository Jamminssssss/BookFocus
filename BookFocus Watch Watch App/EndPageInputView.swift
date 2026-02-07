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
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .safeAreaInset(edge: .bottom) {
                Button {
                    saveSession()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
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

    private func saveSession() {
        guard endPage >= startPage else {
            errorMessage = "마지막 페이지는 시작 페이지보다 작을 수 없습니다."
            showError = true
            return
        }

        let manager = TimerStateManager.shared

        // 책 상태 업데이트
        var updatedBook = book
        updatedBook.currentPage = endPage
        updatedBook.lastUpdated = Date()
        manager.updateBook(updatedBook)

        // 세션 데이터
        let startTime = Date().addingTimeInterval(-elapsedTime)
        let sessionData: [String: Any] = [
            "bookID": book.id,
            "startPage": startPage,
            "endPage": endPage,
            "duration": elapsedTime,
            "startTime": startTime.timeIntervalSince1970,
            "endTime": Date().timeIntervalSince1970
        ]

        // AppGroup 저장
        if let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader") {
            var sessions = defaults.array(forKey: "sessions.data") as? [[String: Any]] ?? []
            sessions.append(sessionData)
            defaults.set(sessions, forKey: "sessions.data")
        }

        // iPhone 전송
        sendSessionToApp(sessionData: sessionData, updatedBook: updatedBook)

        // 콜백으로 TimerView에 갱신 전달
        onSave?(updatedBook)

        manager.clearState()
        dismiss()
    }

    private func sendSessionToApp(sessionData: [String: Any], updatedBook: TimerStateManager.BookData) {
        let session = WCSession.default

        guard
            let sessionJSON = try? JSONSerialization.data(withJSONObject: sessionData),
            let bookJSON = try? JSONEncoder().encode(updatedBook)
        else { return }

        let payload: [String: Any] = [
            "type": "sessionSaved",
            "session": sessionJSON,
            "book": bookJSON
        ]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }
}
