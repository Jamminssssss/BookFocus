import SwiftUI
import WatchConnectivity

struct EndPageInputView: View {
    let book: TimerStateManager.BookData
    let elapsedTime: TimeInterval
    var onSave: ((TimerStateManager.BookData) -> Void)?

    @Environment(\.dismiss) private var dismiss
    private let inkColor = Color.white

    @State private var endPage: Int
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    private var startPage: Int { book.currentPage }

    init(book: TimerStateManager.BookData, elapsedTime: TimeInterval, onSave: ((TimerStateManager.BookData) -> Void)? = nil) {
        self.book = book
        self.elapsedTime = elapsedTime
        self.onSave = onSave
        _endPage = State(initialValue: min(book.currentPage, max(1, book.totalPages)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ⭐️ 전자책 여부에 따라 헤더 분기
                Text(book.isEbook ? "end progress (%)." : "end page.")
                    .font(.custom("ChalkboardSE-Regular", size: 14))
                    .foregroundColor(inkColor.opacity(0.7))
                    .padding(.top, 8)

                // 페이지 증가/감소 컨트롤 (아날로그 테두리 적용)
                HStack(spacing: 12) {
                    Button { endPage = max(startPage, endPage - 1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(inkColor, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || endPage <= startPage)
                    .opacity(endPage <= startPage ? 0.3 : 1.0)

                    // ⭐️ 전자책이면 숫자 뒤에 % 기호 표시
                    Text(book.isEbook ? "\((Double(endPage) / 100).formatted(.percent.precision(.fractionLength(0))))" : "\(endPage)")
                        .font(.custom("ChalkboardSE-Bold", size: 28))
                        .frame(minWidth: 50)
                        .foregroundStyle(inkColor)

                    Button { endPage = min(book.totalPages, endPage + 1) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(inkColor, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || endPage >= book.totalPages)
                    .opacity(endPage >= book.totalPages ? 0.3 : 1.0)
                }
                .padding(.top, 16)

                Spacer(minLength: 0)
                
                // 저장 버튼
                Button(action: saveSession) {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: inkColor)).scaleEffect(0.6)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(isSaving ? "saving..." : "save")
                            .font(.custom("ChalkboardSE-Bold", size: 16))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(inkColor, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
                .disabled(isSaving || endPage < startPage || endPage > book.totalPages)
                .opacity((isSaving || endPage < startPage || endPage > book.totalPages) ? 0.3 : 1.0)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: handleDismiss) {
                        Image(systemName: "xmark").font(.system(size: 16)).foregroundStyle(inkColor)
                    }.disabled(isSaving)
                }
            }
            .alert("Oops", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage).font(.custom("ChalkboardSE-Regular", size: 14)) }
        }
    }
    
    private func handleDismiss() {
        TimerViewModel.shared.cancelRemoteSession(bookID: book.id)
        dismiss()
    }

    private func saveSession() {
        // ⭐️ 책 포맷에 따라 에러메시지 동적 변경 (page vs progress)
        let label = book.isEbook ? "progress" : "page"
        guard endPage >= startPage else { errorMessage = "End \(label) must be >= start \(label)."; showError = true; return }
        guard endPage <= book.totalPages else { errorMessage = "End \(label) cannot exceed total \(label)s."; showError = true; return }
        guard !isSaving else { return }
        
        isSaving = true

        var updatedBook = book
        updatedBook.currentPage = endPage
        updatedBook.lastUpdated = Date()
        TimerStateManager.shared.updateBook(updatedBook)

        let startTime = Date().addingTimeInterval(-elapsedTime)
        let sessionData: [String: Any] = [
            "sessionID": UUID().uuidString,
            "bookID": book.id,
            "startPage": startPage,
            "endPage": endPage,
            "duration": elapsedTime,
            "startTime": startTime.timeIntervalSince1970,
            "endTime": Date().timeIntervalSince1970
        ]

        sendSessionToApp(sessionData: sessionData, updatedBook: updatedBook)

        onSave?(updatedBook)
    }
    
    private func sendSessionToApp(sessionData: [String: Any], updatedBook: TimerStateManager.BookData) {
        guard let sessionJSON = try? JSONSerialization.data(withJSONObject: sessionData),
              let bookJSON = try? JSONEncoder().encode(updatedBook) else { return }
        let payload: [String: Any] = ["type": "sessionSaved", "session": sessionJSON, "book": bookJSON]
        WatchSessionManager.shared.sendSession(payload)
    }
}
