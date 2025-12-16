import SwiftUI
import SwiftData
import AVFoundation
import ActivityKit

struct ReadingTimerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let book: Book

    @State private var sessionStartTime: Date = Date()
    @State private var pausedElapsedTime: TimeInterval = 0
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isRunning: Bool = false
    @State private var currentSession: ReadingSession?
    @State private var showEndPageInput: Bool = false

    // ⏱ Timer mode
    @State private var targetMinutes: Int = 30
    @State private var isTimerMode: Bool = false
    @State private var timerEndDate: Date?

    // UI
    @State private var showTimerPicker: Bool = false
    @State private var showTimerAlert: Bool = false

    // Audio / Live Activity
    @State private var audioPlayer: AVAudioPlayer?
    @State private var activity: Activity<ReadingTimerAttributes>?

    // MARK: - UI
    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 10) {
                if let imagePath = book.imagePath,
                   let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
                   let data = try? Data(contentsOf: documents.appendingPathComponent(imagePath)),
                   let uiImage = UIImage(data: data) {

                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 150)
                        .cornerRadius(10)
                }

                Text(book.title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 20) {
                if isTimerMode {
                    let remaining = max(0, TimeInterval(targetMinutes * 60) - elapsedTime)
                    Text(formatTime(remaining))
                        .font(.system(size: 60, weight: .bold, design: .monospaced))
                        .foregroundColor(remaining < 60 ? .red : .primary)
                } else {
                    Text(formatTime(elapsedTime))
                        .font(.system(size: 60, weight: .bold, design: .monospaced))
                }

                Text("Current Page: \(book.currentPage) / \(book.totalPages)")
                    .font(.headline)
            }
            .padding(.vertical, 40)

            HStack(spacing: 20) {
                Button(action: toggleTimer) {
                    Label(isRunning ? "Pause" : "Start",
                          systemImage: isRunning ? "pause.fill" : "play.fill")
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(isRunning ? Color.orange : Color.green)
                        .cornerRadius(10)
                }

                Button(action: stopTimer) {
                    Label("Stop", systemImage: "stop.fill")
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .cornerRadius(10)
                }
                .disabled(!isRunning && currentSession == nil)
                .opacity((!isRunning && currentSession == nil) ? 0.5 : 1)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Reading Timer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showTimerPicker = true } label: {
                    Image(systemName: "timer")
                }
            }
        }
        .sheet(isPresented: $showEndPageInput) {
            EndPageInputView(book: book, session: currentSession) {
                dismiss()
            }
        }
        .sheet(isPresented: $showTimerPicker) {
            TimerPickerView(minutes: $targetMinutes, isTimerMode: $isTimerMode)
        }
        .alert("Timer Complete!", isPresented: $showTimerAlert) {
            Button("Save Reading") { showEndPageInput = true }
            Button("Cancel", role: .cancel) { resetAfterCompletion() }
        }
        .onAppear {
            endAllLiveActivities()
            checkTimerCompletionOnAppear()
        }
        .onDisappear {
            timer?.invalidate()
            audioPlayer?.stop()
            endLiveActivity()
        }
    }

    // MARK: - Timer Control

    private func toggleTimer() {
        isRunning ? pauseTimer() : (currentSession == nil ? startTimer() : resumeTimer())
    }

    private func startTimer() {
        let now = Date()

        let session = ReadingSession(
            startTime: now,
            startPage: book.currentPage,
            book: book
        )
        modelContext.insert(session)
        book.sessions?.append(session)

        currentSession = session
        sessionStartTime = now
        pausedElapsedTime = 0
        elapsedTime = 0
        isRunning = true

        if isTimerMode {
            timerEndDate = now.addingTimeInterval(TimeInterval(targetMinutes * 60))
            scheduleTimerCompletionNotification(in: TimeInterval(targetMinutes * 60))
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
            scheduleTimerCompletionNotification(in: remaining)
        }

        startLiveActivity()
        startUITimer()
    }

    private func pauseTimer() {
        pausedElapsedTime += Date().timeIntervalSince(sessionStartTime)
        isRunning = false
        timer?.invalidate()

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["timerCompletion"])

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

    private func startUITimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime = pausedElapsedTime + Date().timeIntervalSince(sessionStartTime)

            if isTimerMode, let end = timerEndDate, Date() >= end {
                handleTimerCompletion()
            }
        }
    }

    // MARK: - Completion

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
        currentSession = nil
        pausedElapsedTime = 0
        elapsedTime = 0
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // ⭐ 핵심 수정
        let activityStartDate = Date().addingTimeInterval(-pausedElapsedTime)

        let attributes = ReadingTimerAttributes(
            bookTitle: book.title,
            bookImagePath: book.imagePath,
            sessionStartTime: sessionStartTime
        )

        let contentState = ReadingTimerAttributes.ContentState(
            timerStartDate: activityStartDate,   // ⭕ 누적 반영
            pausedTime: pausedElapsedTime,
            isRunning: true,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes,
            timerEndDate: isTimerMode
                ? activityStartDate.addingTimeInterval(TimeInterval(targetMinutes * 60))
                : nil
        )

        do {
            let content = ActivityContent(state: contentState, staleDate: nil)
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("✅ Live Activity started (elapsed preserved)")
        } catch {
            print("❌ Live Activity error: \(error)")
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

    private func checkTimerCompletionOnAppear() {
        guard isTimerMode,
              let end = timerEndDate,
              Date() >= end,
              isRunning else { return }
        handleTimerCompletion()
    }

    private func scheduleTimerCompletionNotification(in seconds: TimeInterval) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["timerCompletion"])

        let content = UNMutableNotificationContent()
        content.title = "Reading Timer Complete!"
        content.body = "\(targetMinutes) minutes reached."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: "timerCompletion",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
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
    @State private var selectedMinutes: Int
    
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
                    
                    VStack(spacing: 12) {
                        Image(systemName: "timer")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Set Reading Timer")
                            .font(.system(size: 32, weight: .bold))
                        
                        Text("Choose how long you want to read")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 50)
                    
                    Picker("Minutes", selection: $selectedMinutes) {
                        ForEach([1, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120], id: \.self) { min in
                            Text("\(min)").tag(min)
                                .font(.system(size: 24, weight: .semibold))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 180)
                    .padding(.horizontal, 40)
                    
                    Text("minutes")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    Spacer()
                    
                    Button(action: {
                        minutes = selectedMinutes
                        isTimerMode = true
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text("Start Timer")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.blue)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }
}
