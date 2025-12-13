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
    
    @State private var targetMinutes: Int = 30
    @State private var showTimerPicker: Bool = false
    @State private var isTimerMode: Bool = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var showTimerAlert: Bool = false
    
    @State private var activity: Activity<ReadingTimerAttributes>?
    @State private var actionCheckTimer: Timer?
    
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
            Button("OK") {
                stopTimer()
            }
        } message: {
            Text("You've reached your reading goal of \(targetMinutes) minutes!")
        }
        .onAppear {
            endAllLiveActivities()
            setupNotifications()
        }
        .onDisappear {
            timer?.invalidate()
            actionCheckTimer?.invalidate()
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
        
        isRunning = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.startLiveActivity()
        }
        
        startUITimer()
    }
    
    private func resumeTimer() {
        sessionStartTime = Date()
        isRunning = true
        startUITimer()
    }
    
    private func pauseTimer() {
        isRunning = false
        pausedElapsedTime += Date().timeIntervalSince(sessionStartTime)
        timer?.invalidate()
        updateLiveActivity()
    }
    
    private func stopTimer() {
        isRunning = false
        timer?.invalidate()
        audioPlayer?.stop()
        
        if let session = currentSession {
            session.duration = pausedElapsedTime + Date().timeIntervalSince(sessionStartTime)
        }
        
        endLiveActivity()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.showEndPageInput = true
        }
    }
    
    private func startUITimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            elapsedTime = pausedElapsedTime + Date().timeIntervalSince(sessionStartTime)
            updateLiveActivity()
            
            if isTimerMode && elapsedTime >= TimeInterval(targetMinutes * 60) {
                playAlarm()
                showTimerAlert = true
                pauseTimer()
            }
        }
    }
    
    // MARK: - Live Activity
    
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = ReadingTimerAttributes(
            bookTitle: book.title,
            bookImagePath: book.imagePath,
            startTime: sessionStartTime
        )
        
        let contentState = ReadingTimerAttributes.ContentState(
            elapsedTime: elapsedTime,
            isRunning: isRunning,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes
        )
        
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil)
            )
        } catch {
            print("Error starting Live Activity: \(error)")
        }
    }
    
    private func updateLiveActivity() {
        guard let activity = activity else { return }
        
        let contentState = ReadingTimerAttributes.ContentState(
            elapsedTime: elapsedTime,
            isRunning: isRunning,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes
        )
        
        Task {
            await activity.update(using: contentState)
        }
    }
    
    private func endLiveActivity() {
        guard let activity = activity else { return }
        
        Task {
            await activity.end(using: nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
    
    private func endAllLiveActivities() {
        Task {
            for activity in Activity<ReadingTimerAttributes>.activities {
                await activity.end(using: nil, dismissalPolicy: .immediate)
            }
        }
        self.activity = nil
    }
    
    // MARK: - Live Activity Action Monitoring
    
   
    
    private func playAlarm() {
        AudioServicesPlaySystemSound(1005)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// TimerPickerView는 기존 그대로 사용 가능


// 타이머 설정 뷰
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
                        ForEach([5, 10, 15, 20, 25, 30, 45, 60, 90, 120], id: \.self) { min in
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
