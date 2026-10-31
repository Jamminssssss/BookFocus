import SwiftUI
import SwiftData

struct ReadingTimerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    let book: Book
    @ObservedObject private var timerManager = ReadingTimerManager.shared
    @ObservedObject private var focusManager = FocusManager.shared
    
    private var isIPad: Bool { horizontalSizeClass == .regular }
    private var coverHeight: CGFloat { isIPad ? 400 : 260 }
    
    private var isThisBookActive: Bool {
        timerManager.activeBookID == book.id
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack {
                    Spacer()

                    // Book Info
                    VStack(spacing: isIPad ? 16 : 10) {
                        if let imageData = book.coverImageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(height: coverHeight)
                                .cornerRadius(isIPad ? 16 : 10)
                                .shadow(color: .black.opacity(0.2), radius: isIPad ? 15 : 10, x: 0, y: isIPad ? 8 : 5)
                        } else {
                            RoundedRectangle(cornerRadius: isIPad ? 16 : 10)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: coverHeight)
                                .overlay(
                                    Image(systemName: "book.closed")
                                        .font(.system(size: isIPad ? 60 : 40))
                                        .foregroundColor(.white.opacity(0.6))
                                )
                        }

                        Text(book.title).font(isIPad ? .largeTitle : .title2).fontWeight(.bold)
                        Text(book.author).font(isIPad ? .title3 : .subheadline).foregroundColor(.secondary)
                    }

                    if focusManager.isFocusModeActive {
                        HStack(spacing: 6) {
                            Image(systemName: "shield.fill").font(.caption)
                            Text("Focus Mode ON").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.indigo, in: Capsule()).padding(.top, 8)
                    }

                    // ⏱ Time Display
                    VStack(spacing: isIPad ? 28 : 20) {
                        if timerManager.isTimerMode {
                            let remaining = max(0, TimeInterval(timerManager.targetSeconds) - timerManager.elapsedTime)
                            Text(formatTime(isThisBookActive ? remaining : TimeInterval(timerManager.targetSeconds)))
                                .font(.system(size: isIPad ? 80 : 60, weight: .bold, design: .monospaced))
                                .foregroundColor(remaining < 60 && isThisBookActive ? .red : .primary)
                        } else {
                            Text(formatTime(isThisBookActive ? timerManager.elapsedTime : 0))
                                .font(.system(size: isIPad ? 80 : 60, weight: .bold, design: .monospaced))
                        }

                        // ⭐️ 전자책(ebook) 여부에 따라 페이지/퍼센트 텍스트 분기 처리
                        if book.isEbook {
                            Text("Current Progress: \((Double(book.currentPage) / 100).formatted(.percent.precision(.fractionLength(0))))")
                                .font(isIPad ? .title3 : .headline)
                        } else {
                            Text("Current Page: \(book.currentPage) / \(book.totalPages)")
                                .font(isIPad ? .title3 : .headline)
                        }
                    }
                    .padding(.vertical, isIPad ? 60 : 40)

                    // Action Buttons
                    HStack(spacing: isIPad ? 32 : 20) {
                        Button {
                            if !isThisBookActive || timerManager.elapsedTime == 0 {
                                if !timerManager.isTimerMode {
                                    timerManager.targetSeconds = 0
                                    timerManager.cancelPendingNotification()
                                }
                            }
                            
                            TimerStateManager.shared.setActiveBookID(book.id.uuidString)
                            timerManager.toggleTimer(for: book)
                        } label: {
                            Label(isThisBookActive && timerManager.isRunning ? "Pause" : "Start",
                                  systemImage: isThisBookActive && timerManager.isRunning ? "pause.fill" : "play.fill")
                                .font(isIPad ? .title3 : .body).foregroundColor(.white)
                                .frame(width: isIPad ? 160 : 130).padding(.vertical, isIPad ? 18 : 14)
                                .background(isThisBookActive && timerManager.isRunning ? Color.orange : Color.green)
                                .cornerRadius(isIPad ? 14 : 10)
                        }

                        Button {
                            timerManager.stopTimer()
                            dismiss()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .font(isIPad ? .title3 : .body).foregroundColor(.white)
                                .frame(width: isIPad ? 160 : 130).padding(.vertical, isIPad ? 18 : 14)
                                .background(Color.red).cornerRadius(isIPad ? 14 : 10)
                        }
                        .disabled(!isThisBookActive || (!timerManager.isRunning && timerManager.currentSession == nil))
                        .opacity((!isThisBookActive || (!timerManager.isRunning && timerManager.currentSession == nil)) ? 0.5 : 1)
                    }

                    Spacer()
                }
                .padding(isIPad ? 32 : 16)
            }
        }
        .navigationTitle("Reading Timer")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Timer Finished", isPresented: $timerManager.showTimerAlert) {
            Button("Complete Session", role: .none) {
                timerManager.stopTimer()
                dismiss()
            }
            Button("Dismiss", role: .cancel) {
                timerManager.cancelSession()
                dismiss()
            }
        } message: {
            Text("You have reached your target reading time!")
        }
        .onAppear {
            TimerStateManager.shared.setActiveBookID(book.id.uuidString)
            Task { await focusManager.checkAuthorization() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                syncWithWidgetState()
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let h = Int(time) / 3600; let m = Int(time) / 60 % 60; let s = Int(time) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
    
    private func syncWithWidgetState() {
        guard let dbState = TimerStateManager.shared.loadActiveState() else { return }
        
        if dbState.bookID == book.id.uuidString {
            if dbState.isRunning == false && timerManager.isRunning == true {
                timerManager.toggleTimer(for: book)
            }
            else if dbState.isRunning == true && timerManager.isRunning == false {
                timerManager.toggleTimer(for: book)
            }
        }
        
        if let action = TimerStateManager.shared.getWidgetAction() {
            if action == "stop" {
                timerManager.stopTimer()
                dismiss()
            }
        }
    }
}
