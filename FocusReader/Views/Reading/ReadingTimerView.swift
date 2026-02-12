import SwiftUI
import WidgetKit
import SwiftData
import AVFoundation
import ActivityKit
import AppIntents

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
    @State private var currentSession: ReadingSession?
    @State private var showEndPageInput: Bool = false

    // ⏱ Timer mode
    @State private var targetMinutes: Int = 30
    @State private var isTimerMode: Bool = false
    @State private var timerEndDate: Date?

    // UI
    // Removed: @State private var showTimerPicker: Bool = false
    @State private var showTimerAlert: Bool = false

    // Audio / Live Activity
    @State private var activity: Activity<ReadingTimerAttributes>?
    
    // Widget State Manager
    private let stateManager = TimerStateManager.shared
    
    // 디바이스별 크기
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    private var coverHeight: CGFloat {
        isIPad ? 400 : 260
    }
    
    @State private var widgetObserverTimer: Timer?
    @State private var endLiveActivityObserver: NSObjectProtocol?

    var body: some View {
        VStack(spacing: 0) {
            // 🎯 상단 배너
            AdaptiveTopBannerView()
            
            // 메인 컨텐츠
            ScrollView {
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
                                .frame(width: isIPad ? 160 : 130) // 고정 너비 추가
                                .padding(.vertical, isIPad ? 18 : 14)
                                .background(isRunning ? Color.orange : Color.green)
                                .cornerRadius(isIPad ? 14 : 10)
                        }

                        Button(action: stopTimer) {
                            Label("Stop", systemImage: "stop.fill")
                                .font(isIPad ? .title3 : .body)
                                .foregroundColor(.white)
                                .frame(width: isIPad ? 160 : 130) // 고정 너비 추가
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
            }
            
            // 🎯 하단 배너
            AdaptiveBottomBannerView()
        }
        .navigationTitle("Reading Timer")
        .navigationBarTitleDisplayMode(.inline)
        //.toolbar { ... }  <-- Entire toolbar removed according to instructions
        
        .fullScreenCover(isPresented: $showEndPageInput) {
            EndPageInputView(book: book, session: currentSession) {
                if let session = currentSession {
                    book.addSession(session)
                    modelContext.insert(session)
                    try? modelContext.save()
                    print("✅ 세션 저장 완료: \(session.duration)초")
                }
                currentSession = nil
                clearWidgetState()
                dismiss()
            } onCancel: {
                print("❌ 세션 취소됨 - 저장하지 않음")
                cancelSession()
            }
        }
        //.fullScreenCover(isPresented: $showTimerPicker) { TimerPickerView(minutes: $targetMinutes, isTimerMode: $isTimerMode) }  <-- removed as per instructions
        .onAppear {
            endAllLiveActivities()
            setupWidgetStateSync()
            setupWidgetActionObserver()
            
            // EndPageInputView에서 종료 요청 알림 수신
            endLiveActivityObserver = NotificationCenter.default.addObserver(forName: Notification.Name("ReadingTimer.EndLiveActivity"), object: nil, queue: .main) { _ in
                handleEndLiveActivityNotification()
            }
        }
        .onDisappear {
            timer?.invalidate()
            stopWidgetActionObserver()
            // 정리: 진행 중이 아니고, 세션도 없고, EndPageInputView도 열려있지 않다면 위젯/라이브 액티비티 정리
            if !isRunning && currentSession == nil && !showEndPageInput {
                endLiveActivity()
                clearWidgetState()
            }
            if let token = endLiveActivityObserver {
                NotificationCenter.default.removeObserver(token)
                endLiveActivityObserver = nil
            }
        }
    }

    // MARK: - Timer Control

    private func toggleTimer() {
        isRunning ? pauseTimer() : (currentSession == nil ? startTimer() : resumeTimer())
    }

    private func startTimer() {
        let now = Date()
        
        let newSession = ReadingSession(
            startTime: now,
            startPage: book.currentPage
        )
        currentSession = newSession

        sessionStartTime = now
        pausedElapsedTime = 0
        elapsedTime = 0
        isRunning = true

        if isTimerMode {
            timerEndDate = now.addingTimeInterval(TimeInterval(targetMinutes * 60))
        }

        startLiveActivity()
        startUITimer()
        updateLiveActivity()
        updateWidgetState()
        
        print("🚀 타이머 시작: 임시 세션 생성됨 (SwiftData에 아직 저장 안 됨)")
    }

    private func resumeTimer() {
        sessionStartTime = Date()
        isRunning = true

        if isTimerMode {
            let remaining = max(0, TimeInterval(targetMinutes * 60) - pausedElapsedTime)
            timerEndDate = Date().addingTimeInterval(remaining)
        }

        // 라이브 액티비티 재요청 대신 상태 업데이트
        startUITimer()
        updateLiveActivity()
        updateWidgetState()
    }

    private func pauseTimer() {
        pausedElapsedTime += Date().timeIntervalSince(sessionStartTime)
        isRunning = false
        timer?.invalidate()
        // 라이브 액티비티 종료 대신 상태 업데이트
        updateLiveActivity()
        updateWidgetState()
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
        // 위젯 상태는 유지 (EndPageInputView에서 처리)
        updateWidgetState()
        showEndPageInput = true
    }

    private func cancelSession() {
        print("🗑️ 세션 취소: duration=\(currentSession?.duration ?? 0)초 (저장 안 함)")
        
        currentSession = nil
        resetAfterCompletion()
        clearWidgetState()
        modelContext.rollback()
    }

    private func startUITimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime = pausedElapsedTime + Date().timeIntervalSince(sessionStartTime)

            if isTimerMode, let end = timerEndDate, Date() >= end {
                handleTimerCompletion()
            }
            
            // 위젯/라이브 액티비티 상태 업데이트 (1초마다)
            updateWidgetState()
            updateLiveActivity()
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

        updateLiveActivity()
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
    
    private func updateLiveActivity() {
        guard let activity = activity else { return }
        let activityStartDate = Date().addingTimeInterval(-pausedElapsedTime)
        let contentState = ReadingTimerAttributes.ContentState(
            timerStartDate: activityStartDate,
            pausedTime: pausedElapsedTime,
            isRunning: isRunning,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes,
            timerEndDate: isTimerMode ? timerEndDate : nil,
            currentPage: book.currentPage,
            totalPages: book.totalPages
        )
        Task { await activity.update(ActivityContent(state: contentState, staleDate: nil)) }
    }
    
    private func handleEndLiveActivityNotification() {
        // 라이브 액티비티 종료 요청 처리
        endLiveActivity()
        // 진행 중이 아니고 세션이 없으면 위젯 상태도 정리
        if !isRunning && currentSession == nil {
            clearWidgetState()
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
    
    // MARK: - Widget State Sync
    
    private func setupWidgetStateSync() {
        // 초기 상태를 위젯에 저장
        updateWidgetState()
    }
    
    private func setupWidgetActionObserver() {
        widgetObserverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            
            if let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader"),
               let action = defaults.string(forKey: "widget.action") {
                
                defaults.removeObject(forKey: "widget.action")
                
                if action == "stop" && defaults.bool(forKey: "widget.openEndPageInput") {
                    defaults.synchronize()
                    return
                }
                
                defaults.synchronize()
                
                DispatchQueue.main.async {
                    if action == "toggle" {
                        // ⭐ 위젯에서 이미 시간 계산을 완료했으므로
                        // 위젯 상태를 다시 로드하여 동기화
                        if let widgetState = TimerStateManager.shared.loadState() {
                            self.syncWithWidgetState(widgetState)
                        }
                    }
                }
            }
            
            if let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader"),
               let action = defaults.string(forKey: "watch.action") {
                
                defaults.removeObject(forKey: "watch.action")
                defaults.synchronize()
                
                DispatchQueue.main.async {
                    if action == "start" || action == "resume" {
                        if !self.isRunning {
                            if self.currentSession == nil {
                                self.startTimer()
                            } else {
                                self.resumeTimer()
                            }
                        }
                    } else if action == "pause" {
                        if self.isRunning {
                            self.pauseTimer()
                        }
                    } else if action == "stop" {
                        self.stopTimer()
                    }
                }
            }
        }
    }
    
    private func stopWidgetActionObserver() {
        widgetObserverTimer?.invalidate()
        widgetObserverTimer = nil
    }
    
    
    
    // ⭐ 새로운 함수: 위젯 상태와 앱 상태 동기화
    private func syncWithWidgetState(_ widgetState: TimerStateManager.TimerState) {
        print("🔄 Syncing with widget state - isRunning: \(widgetState.isRunning), pausedTime: \(widgetState.pausedTime)")
        
        if widgetState.isRunning {
            // 위젯에서 재개됨
            if !isRunning {
                // 앱에서 일시정지 상태였음 -> 재개
                pausedElapsedTime = widgetState.pausedTime
                sessionStartTime = Date()
                isRunning = true
                
                // Timer Mode 처리
                if isTimerMode {
                    let totalTargetTime = TimeInterval(targetMinutes * 60)
                    let remainingTime = max(0, totalTargetTime - pausedElapsedTime)
                    timerEndDate = Date().addingTimeInterval(remainingTime)
                }
                
                startUITimer()
                updateLiveActivity()
                updateWidgetState()
                
                print("▶️ App resumed from widget")
            }
        } else {
            // 위젯에서 일시정지됨
            if isRunning {
                // 앱에서 실행 중이었음 -> 일시정지
                pausedElapsedTime = widgetState.pausedTime
                elapsedTime = pausedElapsedTime
                isRunning = false
                timer?.invalidate()
                
                updateLiveActivity()
                updateWidgetState()
                
                print("⏸ App paused from widget - pausedTime: \(pausedElapsedTime)")
            } else {
                // 둘 다 일시정지 상태 -> 시간만 동기화
                pausedElapsedTime = widgetState.pausedTime
                elapsedTime = pausedElapsedTime
                updateWidgetState()
                
                print("🔄 Time synced with widget - pausedTime: \(pausedElapsedTime)")
            }
        }
    }
    
    private func updateWidgetState() {
        // ⭐ 현재 경과 시간을 정확하게 계산하여 저장
        let currentElapsedTime: TimeInterval
        if isRunning {
            currentElapsedTime = pausedElapsedTime + Date().timeIntervalSince(sessionStartTime)
        } else {
            currentElapsedTime = pausedElapsedTime
        }
        
        let state = TimerStateManager.TimerState(
            isRunning: isRunning,
            bookTitle: book.title,
            currentPage: book.currentPage,
            totalPages: book.totalPages,
            elapsedTime: currentElapsedTime,
            sessionStartTime: isRunning ? sessionStartTime : nil,
            pausedTime: pausedElapsedTime,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes,
            timerEndDate: timerEndDate,
            bookID: book.id.uuidString
        )
        
        stateManager.saveState(state)
        
        // ⭐ 위젯에도 즉시 반영
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func clearWidgetState() {
        stateManager.clearState()
    }
}






