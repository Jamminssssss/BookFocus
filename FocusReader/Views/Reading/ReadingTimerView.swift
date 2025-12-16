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
    
    // Date 기반 추가
    @State private var timerStartDate: Date?
    @State private var timerEndDate: Date?
    
    @State private var targetMinutes: Int = 30
    @State private var showTimerPicker: Bool = false
    @State private var isTimerMode: Bool = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var showTimerAlert: Bool = false
    
    @State private var activity: Activity<ReadingTimerAttributes>?
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 10) {
                if let imagePath = book.imagePath,
                   let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let imageURL = documentsDirectory.appendingPathComponent(imagePath)
                    if let imageData = try? Data(contentsOf: imageURL),
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                            .cornerRadius(10)
                    }
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
                        .foregroundColor(.primary)
                }
                
                Text("Current Page: \(book.currentPage) / \(book.totalPages)")
                    .font(.headline)
            }
            .padding(.vertical, 40)
            
            HStack(spacing: 20) {
                Button(action: toggleTimer) {
                    Label(isRunning ? "Pause" : "Start",
                          systemImage: isRunning ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(isRunning ? Color.orange : Color.green)
                        .cornerRadius(10)
                }
                .disabled(isTimerMode && elapsedTime >= TimeInterval(targetMinutes * 60))
                
                Button(action: stopTimer) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .cornerRadius(10)
                }
                .disabled(!isRunning && currentSession == nil)
                .opacity((!isRunning && currentSession == nil) ? 0.5 : 1)
            }
            .padding(.top, 20)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Reading Timer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showTimerPicker = true }) {
                    Image(systemName: "timer")
                        .font(.title3)
                }
            }
        }
        .sheet(isPresented: $showEndPageInput) {
            EndPageInputView(
                book: book,
                session: currentSession,
                onComplete: {
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showTimerPicker) {
            TimerPickerView(minutes: $targetMinutes, isTimerMode: $isTimerMode)
                .presentationDetents([.large])
        }
        .alert("Timer Complete!", isPresented: $showTimerAlert) {
            Button("Save Reading") {
                showEndPageInput = true
            }
            Button("Cancel", role: .cancel) {
                resetAfterCompletion()
            }
        } message: {
            Text("You've reached your reading goal of \(targetMinutes) minutes!")
        }
        .onAppear {
            endAllLiveActivities()
            setupNotifications()
            setupBackgroundTask()
            checkTimerCompletionOnAppear()
        }
        .onDisappear {
            timer?.invalidate()
            audioPlayer?.stop()
            endLiveActivity()
            NotificationCenter.default.removeObserver(self)
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ToggleTimer"),
            object: nil,
            queue: .main
        ) { _ in
            self.toggleTimer()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("StopTimer"),
            object: nil,
            queue: .main
        ) { _ in
            self.stopTimer()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.scheduleBackgroundTask()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.checkTimerCompletionOnAppear()
        }
    }
    
    private func setupBackgroundTask() {
        guard isTimerMode, let endDate = timerEndDate else { return }
        
        let remaining = endDate.timeIntervalSinceNow
        if remaining > 0 {
            scheduleTimerCompletionNotification(in: remaining)
        }
    }
    
    private func scheduleBackgroundTask() {
        guard isTimerMode, let endDate = timerEndDate, isRunning else { return }
        
        let remaining = endDate.timeIntervalSinceNow
        if remaining > 0 {
            print("📱 Scheduling background task for \(remaining) seconds")
            scheduleTimerCompletionNotification(in: remaining)
        }
    }
    
    private func scheduleTimerCompletionNotification(in timeInterval: TimeInterval) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timerCompletion"])
        
        let content = UNMutableNotificationContent()
        content.title = "Reading Timer Complete!"
        content.body = "You've reached your reading goal of \(targetMinutes) minutes!"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: "timerCompletion", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error scheduling notification: \(error)")
            } else {
                print("✅ Timer completion notification scheduled")
            }
        }
    }
    
    private func toggleTimer() {
        if isRunning {
            pauseTimer()
        } else {
            if currentSession == nil {
                startTimer()
            } else {
                resumeTimer()
            }
        }
    }
    
    // MARK: - Timer Controls
    
    private func startTimer() {
        endLiveActivity()
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permission granted")
            }
        }
        
        let now = Date()
        let session = ReadingSession(
            startTime: now,
            startPage: book.currentPage,
            book: book
        )
        modelContext.insert(session)
        
        if book.sessions == nil {
            book.sessions = []
        }
        book.sessions?.append(session)
        
        currentSession = session
        sessionStartTime = now
        pausedElapsedTime = 0
        elapsedTime = 0
        
        timerStartDate = now
        
        if isTimerMode {
            timerEndDate = now.addingTimeInterval(TimeInterval(targetMinutes * 60))
            scheduleTimerCompletionNotification(in: TimeInterval(targetMinutes * 60))
        } else {
            timerEndDate = nil
        }
        
        isRunning = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.startLiveActivity()
        }
        
        startUITimer()
    }
    
    private func resumeTimer() {
        sessionStartTime = Date()
        timerStartDate = Date()
        
        if isTimerMode {
            let remaining = max(0, TimeInterval(targetMinutes * 60) - pausedElapsedTime)
            timerEndDate = Date().addingTimeInterval(remaining)
            scheduleTimerCompletionNotification(in: remaining)
        }
        
        isRunning = true
        startUITimer()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateLiveActivity()
        }
    }
    
    private func pauseTimer() {
        isRunning = false
        pausedElapsedTime += Date().timeIntervalSince(sessionStartTime)
        timerStartDate = nil
        timer?.invalidate()
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timerCompletion"])
        
        updateLiveActivity()
    }
    
    private func stopTimer() {
        isRunning = false
        timer?.invalidate()
        audioPlayer?.stop()
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timerCompletion"])
        
        if let session = currentSession {
            session.duration = pausedElapsedTime + (isRunning ? Date().timeIntervalSince(sessionStartTime) : 0)
        }
        
        endLiveActivity()
        
        timerStartDate = nil
        timerEndDate = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.showEndPageInput = true
        }
    }
    
    private func startUITimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedTime = pausedElapsedTime + Date().timeIntervalSince(sessionStartTime)
            
            if isTimerMode {
                let remaining = TimeInterval(targetMinutes * 60) - elapsedTime
                
                // 타이머 완료 - 자동 종료
                if remaining <= 0 {
                    handleTimerCompletion()
                }
            }
            
            // 백그라운드에서 타이머가 완료되었는지 체크
            if isTimerMode, let endDate = timerEndDate, Date() >= endDate, isRunning {
                handleTimerCompletion()
            }
        }
    }
    
    // MARK: - Timer Completion Handler
    
    private func handleTimerCompletion() {
        // 백그라운드 알림 취소
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timerCompletion"])
        
        // 알람 재생
        playAlarm()
        
        // 타이머 완전 종료
        timer?.invalidate()
        isRunning = false
        pausedElapsedTime = TimeInterval(targetMinutes * 60)
        elapsedTime = TimeInterval(targetMinutes * 60)
        
        // 세션 저장
        if let session = currentSession {
            session.duration = TimeInterval(targetMinutes * 60)
        }
        
        // Live Activity 즉시 종료
        endLiveActivity()
        
        // 상태 초기화
        timerStartDate = nil
        timerEndDate = nil
        
        // 알림 표시
        showTimerAlert = true
    }
    
    private func resetAfterCompletion() {
        currentSession = nil
        pausedElapsedTime = 0
        elapsedTime = 0
    }
    
    // MARK: - Live Activity
    
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities not enabled")
            return
        }
        
        let attributes = ReadingTimerAttributes(
            bookTitle: book.title,
            bookImagePath: book.imagePath,
            sessionStartTime: sessionStartTime
        )
        
        let contentState = ReadingTimerAttributes.ContentState(
            timerStartDate: timerStartDate,
            pausedTime: pausedElapsedTime,
            isRunning: isRunning,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes,
            timerEndDate: timerEndDate
        )
        
        do {
            let content = ActivityContent(
                state: contentState,
                staleDate: nil
            )
            
            activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            
            print("✅ Live Activity started (Date-based)")
        } catch {
            print("❌ Error starting Live Activity: \(error.localizedDescription)")
        }
    }
    
    private func updateLiveActivity() {
        guard let activity = activity else { return }
        
        let timerEnd = isTimerMode ? Date().addingTimeInterval(max(0, TimeInterval(targetMinutes * 60) - elapsedTime)) : nil
        
        let contentState = ReadingTimerAttributes.ContentState(
            timerStartDate: timerStartDate,
            pausedTime: isRunning ? 0 : pausedElapsedTime,
            isRunning: isRunning,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes,
            timerEndDate: timerEnd
        )
        
        let content = ActivityContent(
            state: contentState,
            staleDate: nil
        )
        
        Task { @MainActor in
            await activity.update(content)
            print("🔄 Live Activity updated (Date-based)")
        }
    }
    
    private func endLiveActivityOnCompletion() async {
        guard let activity = activity else { return }
        
        let completedState = ReadingTimerAttributes.ContentState(
            timerStartDate: nil,
            pausedTime: TimeInterval(targetMinutes * 60),
            isRunning: false,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes,
            timerEndDate: nil
        )
        
        await activity.end(
            ActivityContent(state: completedState, staleDate: nil),
            dismissalPolicy: .immediate
        )
        
        self.activity = nil
        print("✅ Live Activity ended - Timer completed")
    }
    
    private func endLiveActivity() {
        guard let activity = activity else { return }
        
        Task { @MainActor in
            await activity.end(nil, dismissalPolicy: .immediate)
            print("⏹️ Live Activity ended")
        }
        
        self.activity = nil
    }
    
    private func endAllLiveActivities() {
        Task { @MainActor in
            for activity in Activity<ReadingTimerAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        self.activity = nil
    }
    
    private func playAlarm() {
        AudioServicesPlaySystemSound(1005)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    
    private func checkTimerCompletionOnAppear() {
        guard isTimerMode, let endDate = timerEndDate, Date() >= endDate, isRunning else { return }
        
        print("⏰ Timer completed while in background")
        handleTimerCompletion()
    }
    
    // MARK: - 통일된 시간 포맷팅 함수
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        // 1시간 이상: h:mm:ss
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        // 1시간 미만: m:ss
        else {
            return String(format: "%d:%02d", minutes, seconds)
        }
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
