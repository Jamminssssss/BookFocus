import SwiftUI
import SwiftData
import AVFoundation
import ActivityKit

struct ReadingTimerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let book: Book

    @State private var sessionStartTime: Date = Date()
    @State private var pausedElapsedTime: TimeInterval = 0
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isRunning: Bool = false
    @State private var currentSession: ReadingSession? // 임시 세션
    @State private var showEndPageInput: Bool = false

    // ⏱ Timer mode
    @State private var targetMinutes: Int = 30
    @State private var isTimerMode: Bool = false
    @State private var timerEndDate: Date?

    // UI
    @State private var showTimerPicker: Bool = false
    @State private var showTimerAlert: Bool = false

    // Audio / Live Activity
    @State private var activity: Activity<ReadingTimerAttributes>?
    
    // 디바이스별 크기
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    private var coverHeight: CGFloat {
        isIPad ? 400 : 260
    }

    var body: some View {
        VStack {
            Spacer()

            // 책 정보
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
                    // 이미지 없는 경우 placeholder
                    RoundedRectangle(cornerRadius: isIPad ? 16 : 10)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: coverHeight)
                        .overlay(
                            Image(systemName: "book.closed")
                                .font(.system(size: isIPad ? 60 : 40))
                                .foregroundColor(.white.opacity(0.6))
                        )
                }

                Text(book.title)
                    .font(isIPad ? .largeTitle : .title2)
                    .fontWeight(.bold)

                Text(book.author)
                    .font(isIPad ? .title3 : .subheadline)
                    .foregroundColor(.secondary)
            }

            // 타이머/페이지
            VStack(spacing: isIPad ? 28 : 20) {
                if isTimerMode {
                    let remaining = max(0, TimeInterval(targetMinutes * 60) - elapsedTime)
                    Text(formatTime(remaining))
                        .font(.system(size: isIPad ? 80 : 60, weight: .bold, design: .monospaced))
                        .foregroundColor(remaining < 60 ? .red : .primary)
                } else {
                    Text(formatTime(elapsedTime))
                        .font(.system(size: isIPad ? 80 : 60, weight: .bold, design: .monospaced))
                }

                Text("Current Page: \(book.currentPage) / \(book.totalPages)")
                    .font(isIPad ? .title3 : .headline)
            }
            .padding(.vertical, isIPad ? 60 : 40)

            // 컨트롤 버튼
            HStack(spacing: isIPad ? 32 : 20) {
                Button(action: toggleTimer) {
                    Label(isRunning ? "Pause" : "Start",
                          systemImage: isRunning ? "pause.fill" : "play.fill")
                        .font(isIPad ? .title3 : .body)
                        .foregroundColor(.white)
                        .padding(.horizontal, isIPad ? 50 : 40)
                        .padding(.vertical, isIPad ? 18 : 14)
                        .background(isRunning ? Color.orange : Color.green)
                        .cornerRadius(isIPad ? 14 : 10)
                }

                Button(action: stopTimer) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(isIPad ? .title3 : .body)
                        .foregroundColor(.white)
                        .padding(.horizontal, isIPad ? 50 : 40)
                        .padding(.vertical, isIPad ? 18 : 14)
                        .background(Color.red)
                        .cornerRadius(isIPad ? 14 : 10)
                }
                .disabled(!isRunning && currentSession == nil)
                .opacity((!isRunning && currentSession == nil) ? 0.5 : 1)
            }

            Spacer()
        }
        .padding(isIPad ? 32 : 16)
        .navigationTitle("Reading Timer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showTimerPicker = true } label: {
                    Image(systemName: "timer")
                        .font(isIPad ? .title2 : .body)
                }
            }
        }
        .sheet(isPresented: $showEndPageInput) {
            EndPageInputView(book: book, session: currentSession) {
                // Save 버튼 눌렀을 때만 CoreData에 저장
                if let session = currentSession {
                    modelContext.insert(session)
                    if book.sessions == nil {
                        book.sessions = []
                    }
                    book.sessions?.append(session)
                    try? modelContext.save()
                }
                currentSession = nil
                dismiss()
            }
        }
        .sheet(isPresented: $showTimerPicker) {
            TimerPickerView(minutes: $targetMinutes, isTimerMode: $isTimerMode)
        }
        .alert("Timer Complete!", isPresented: $showTimerAlert) {
            Button("Save Reading") { showEndPageInput = true }
            Button("Cancel", role: .cancel) { cancelSession() }
        }
        .onAppear {
            endAllLiveActivities()
        }
        .onDisappear {
            timer?.invalidate()
            endLiveActivity()
        }
    }

    // MARK: - Timer Control

    private func toggleTimer() {
        isRunning ? pauseTimer() : (currentSession == nil ? startTimer() : resumeTimer())
    }

    private func startTimer() {
        let now = Date()
        // 임시 세션 생성 (CoreData insert X, book.sessions append X)
        currentSession = ReadingSession(
            startTime: now,
            startPage: book.currentPage,
            book: book
        )

        sessionStartTime = now
        pausedElapsedTime = 0
        elapsedTime = 0
        isRunning = true

        if isTimerMode {
            timerEndDate = now.addingTimeInterval(TimeInterval(targetMinutes * 60))
        }

        startLiveActivity()
        startUITimer()
    }

    private func resumeTimer() {
        sessionStartTime = Date()
        isRunning = true

        if isTimerMode {
            let remaining = max(0, TimeInterval(targetMinutes * 60) - pausedElapsedTime)
            timerEndDate = Date().addingTimeInterval(remaining)
        }

        startLiveActivity()
        startUITimer()
    }

    private func pauseTimer() {
        pausedElapsedTime += Date().timeIntervalSince(sessionStartTime)
        isRunning = false
        timer?.invalidate()
        endLiveActivity()
    }

    private func stopTimer() {
        let finalElapsed = pausedElapsedTime +
            (isRunning ? Date().timeIntervalSince(sessionStartTime) : 0)

        isRunning = false
        timer?.invalidate()

        if let session = currentSession {
            session.duration = finalElapsed
        }

        endLiveActivity()
        showEndPageInput = true
    }

    private func cancelSession() {
        // Cancel 시 CoreData에 절대 insert하지 않고 임시 세션만 삭제
        currentSession = nil
        resetAfterCompletion()
    }

    private func startUITimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime = pausedElapsedTime + Date().timeIntervalSince(sessionStartTime)

            if isTimerMode, let end = timerEndDate, Date() >= end {
                handleTimerCompletion()
            }
        }
    }

    private func handleTimerCompletion() {
        timer?.invalidate()
        isRunning = false

        pausedElapsedTime = TimeInterval(targetMinutes * 60)
        elapsedTime = pausedElapsedTime

        if let session = currentSession {
            session.duration = pausedElapsedTime
        }

        endLiveActivity()
        playAlarm()
        showTimerAlert = true
    }

    private func resetAfterCompletion() {
        pausedElapsedTime = 0
        elapsedTime = 0
        isRunning = false
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let activityStartDate = Date().addingTimeInterval(-pausedElapsedTime)

        let attributes = ReadingTimerAttributes(
            bookTitle: book.title,
            sessionStartTime: sessionStartTime
        )

        let contentState = ReadingTimerAttributes.ContentState(
            timerStartDate: activityStartDate,
            pausedTime: pausedElapsedTime,
            isRunning: true,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes,
            timerEndDate: isTimerMode
                ? activityStartDate.addingTimeInterval(TimeInterval(targetMinutes * 60))
                : nil,
            currentPage: book.currentPage,
            totalPages: book.totalPages
        )

        do {
            let content = ActivityContent(state: contentState, staleDate: nil)
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("✅ Live Activity 시작 성공")
        } catch {
            print("❌ Live Activity 오류: \(error)")
        }
    }

    private func endLiveActivity() {
        guard let activity = activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }

    private func endAllLiveActivities() {
        Task {
            for activity in Activity<ReadingTimerAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Utils

    private func playAlarm() {
        AudioServicesPlaySystemSound(1005)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let h = Int(time) / 3600
        let m = Int(time) / 60 % 60
        let s = Int(time) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}




// MARK: - Timer Picker View

struct TimerPickerView: View {
    @Binding var minutes: Int
    @Binding var isTimerMode: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedMinutes: Int
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    init(minutes: Binding<Int>, isTimerMode: Binding<Bool>) {
        self._minutes = minutes
        self._isTimerMode = isTimerMode
        self._selectedMinutes = State(initialValue: minutes.wrappedValue)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Spacer()
                    
                    VStack(spacing: isIPad ? 16 : 12) {
                        Image(systemName: "timer")
                            .font(.system(size: isIPad ? 80 : 60))
                            .foregroundColor(.blue)
                        
                        Text("Set Reading Timer")
                            .font(.system(size: isIPad ? 40 : 32, weight: .bold))
                        
                        Text("Choose how long you want to read")
                            .font(isIPad ? .title3 : .subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, isIPad ? 70 : 50)
                    
                    Picker("Minutes", selection: $selectedMinutes) {
                        ForEach([1, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120], id: \.self) { min in
                            Text("\(min)").tag(min)
                                .font(.system(size: isIPad ? 32 : 24, weight: .semibold))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: isIPad ? 220 : 180)
                    .padding(.horizontal, isIPad ? 60 : 40)
                    
                    Text("minutes")
                        .font(isIPad ? .largeTitle : .title2)
                        .foregroundColor(.secondary)
                        .padding(.top, isIPad ? 12 : 8)
                    
                    Spacer()
                    
                    Button(action: {
                        minutes = selectedMinutes
                        isTimerMode = true
                        dismiss()
                    }) {
                        HStack(spacing: isIPad ? 12 : 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(isIPad ? .title2 : .title3)
                            Text("Start Timer")
                                .font(isIPad ? .title3 : .headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isIPad ? 22 : 18)
                        .background(Color.blue)
                        .cornerRadius(isIPad ? 16 : 14)
                    }
                    .padding(.horizontal, isIPad ? 50 : 30)
                    .padding(.bottom, isIPad ? 60 : 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(isIPad ? .title2 : .title3)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
}
