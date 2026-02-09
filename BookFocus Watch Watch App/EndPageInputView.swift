//
//  EndPageInputView.swift
//  BookFocus Watch Watch App
//
//  Refactored: Shows start page, saves end page, and triggers ContentView refresh
//  Updated: Ensures lastUpdated is set for proper data sync
//

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

    init(
        book: TimerStateManager.BookData,
        elapsedTime: TimeInterval,
        onSave: ((TimerStateManager.BookData) -> Void)? = nil
    ) {
        self.book = book
        self.elapsedTime = elapsedTime
        self.onSave = onSave
        _endPage = State(initialValue: book.currentPage)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // End Page Label (moved to top)
                Text("End Page")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                // End Page Input
                HStack(spacing: 10) {
                    Button {
                        endPage = max(startPage, endPage - 1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving || endPage <= startPage)

                    Text("\(endPage)")
                        .font(.system(size: 26, weight: .bold))
                        .frame(minWidth: 44)

                    Button {
                        endPage = min(book.totalPages, endPage + 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving || endPage >= book.totalPages)
                }
                .padding(.top, 12)

                Spacer(minLength: 0)
                
                // Save Button
                Button {
                    saveSession()
                } label: {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                        }
                        Text(isSaving ? "Saving..." : "Save")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .disabled(isSaving || endPage < startPage || endPage > book.totalPages)
            }
            .padding(.horizontal, 8)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        handleDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14))
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Dismiss Handler
    
    private func handleDismiss() {
        // Reset timer for this book without saving
        TimerViewModel.shared.stopTimer(for: book.id)
        dismiss()
    }

    // MARK: - Save Session

    private func saveSession() {
        // Validation
        guard endPage >= startPage else {
            errorMessage = "End page must be greater than or equal to start page."
            showError = true
            return
        }
        
        guard endPage <= book.totalPages else {
            errorMessage = "End page cannot exceed total pages."
            showError = true
            return
        }
        
        guard !isSaving else {
            print("⚠️ Already saving, ignoring duplicate save request")
            return
        }
        
        isSaving = true
        print("🔄 Starting save process...")
        print("📖 Book: \(book.title)")
        print("📄 Pages: \(startPage) → \(endPage)")
        print("⏱ Duration: \(formatTime(elapsedTime))")

        // 1️⃣ Update local book state
        var updatedBook = book
        updatedBook.currentPage = endPage
        updatedBook.lastUpdated = Date()  // ✅ 중요: lastUpdated 업데이트!
        
        print("⏰ Updated lastUpdated: \(updatedBook.lastUpdated)")
        
        TimerStateManager.shared.updateBook(updatedBook)
        print("✅ Local book state updated")

        // 2️⃣ Create session data
        let startTime = Date().addingTimeInterval(-elapsedTime)
        let sessionData: [String: Any] = [
            "bookID": book.id,
            "startPage": startPage,
            "endPage": endPage,
            "duration": elapsedTime,
            "startTime": startTime.timeIntervalSince1970,
            "endTime": Date().timeIntervalSince1970
        ]

        // 3️⃣ Save to AppGroup (fallback mechanism)
        saveToAppGroup(sessionData: sessionData)

        // 4️⃣ Send to iPhone app
        sendSessionToApp(sessionData: sessionData, updatedBook: updatedBook)

        // 5️⃣ Callback and cleanup
        onSave?(updatedBook)
        
        print("✅ Save process completed")
        
        // Delay dismiss to ensure sync completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isSaving = false
            dismiss()
        }
    }
    
    // MARK: - AppGroup Fallback
    
    private func saveToAppGroup(sessionData: [String: Any]) {
        guard let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader") else {
            print("❌ Failed to access AppGroup")
            return
        }
        
        var sessions = defaults.array(forKey: "sessions.data") as? [[String: Any]] ?? []
        sessions.append(sessionData)
        defaults.set(sessions, forKey: "sessions.data")
        
        let synced = defaults.synchronize()
        print("💾 Session saved to AppGroup (fallback): \(synced ? "✅ SUCCESS" : "❌ FAILED")")
        
        if let savedSessions = defaults.array(forKey: "sessions.data") as? [[String: Any]] {
            print("   AppGroup now has \(savedSessions.count) session(s)")
        }
    }

    // MARK: - Send to iPhone
    
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

        print("📤 Attempting to send session to iPhone app...")
        
        let session = WCSession.default
        print("📡 WCSession - Activated: \(session.activationState.rawValue), Reachable: \(session.isReachable)")
        
        WatchSessionManager.shared.sendMessage(payload)
        print("📤 Session sent via WatchSessionManager")
    }
    
    // MARK: - Helpers
    
    private func formatTime(_ time: TimeInterval) -> String {
        let h = Int(time) / 3600
        let m = Int(time) / 60 % 60
        let s = Int(time) % 60
        
        if h > 0 {
            return String(format: "%dh %dm %ds", h, m, s)
        } else if m > 0 {
            return String(format: "%dm %ds", m, s)
        } else {
            return String(format: "%ds", s)
        }
    }
}
