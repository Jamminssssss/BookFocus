import SwiftUI
import Combine
import ActivityKit
import SwiftData
import UserNotifications
import AudioToolbox

@MainActor
final class ReadingTimerManager: ObservableObject {
    static let shared = ReadingTimerManager()
    
    @Published var activeBookID: UUID?
    @Published var activeBookTitle: String = ""
    @Published var activeBookCurrentPage: Int = 1
    @Published var activeBookTotalPages: Int = 1
    @Published var activeBookFormat: String = BookFormat.physical.rawValue
    
    @Published var sessionStartTime: Date = Date()
    @Published var pausedElapsedTime: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var isRunning: Bool = false
    @Published var currentSession: ReadingSession?
    
    @Published var isTimerMode: Bool = false
    @Published var targetSeconds: Int = 1800
    @Published var timerEndDate: Date?
    
    var targetMinutes: Int { max(1, targetSeconds / 60) }
    
    @Published var showTimerAlert: Bool = false
    @Published var showEndPageInput: Bool = false
    
    private var timer: Timer?
    private var activity: Activity<ReadingTimerAttributes>?
    private let stateManager = TimerStateManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        restoreStateOnLaunch()
        setupReactiveWidgetObservers()
        setupTerminationObserver()
    }
    
    func toggleTimer(for book: Book) {
        if let currentID = activeBookID, currentID != book.id {
            stopTimer()
            // Preserve the current session and ask for its ending page before a
            // different book can be started.
            return
        } else {
            isRunning ? pauseTimer() : (currentSession == nil ? startTimer(for: book) : resumeTimer())
        }
    }
    
    func startTimer(for book: Book) {
        let now = Date()
        let newSession = ReadingSession(startTime: now, startPage: book.currentPage)
        self.currentSession = newSession
        
        self.activeBookID = book.id
        self.activeBookTitle = book.title
        self.activeBookCurrentPage = book.currentPage
        self.activeBookTotalPages = book.totalPages
        self.activeBookFormat = book.formatRawValue
        
        if let data = book.coverImageData {
            TimerStateManager.shared.saveCoverImage(data, forBookID: book.id.uuidString)
        }
        
        self.sessionStartTime = now
        self.pausedElapsedTime = 0
        self.elapsedTime = 0
        self.isRunning = true
        
        if isTimerMode {
            self.timerEndDate = now.addingTimeInterval(TimeInterval(targetSeconds))
            scheduleLocalNotificationIfNeeded()
        } else {
            cancelPendingNotification()
        }
        
        startLiveActivity()
        startUITimer()
        updateWidgetState()
        
        syncToWatch(action: "start")
        FocusManager.shared.enableFocusMode()
    }
    
    func resumeTimer() {
        sessionStartTime = Date()
        isRunning = true
        
        if isTimerMode {
            let remaining = max(0, TimeInterval(targetSeconds) - pausedElapsedTime)
            timerEndDate = Date().addingTimeInterval(remaining)
            scheduleLocalNotificationIfNeeded()
        }
        
        startUITimer()
        updateLiveActivity()
        updateWidgetState()
        
        syncToWatch(action: "start")
        FocusManager.shared.enableFocusMode()
    }
    
    func pauseTimer() {
        pausedElapsedTime += Date().timeIntervalSince(sessionStartTime)
        isRunning = false
        timer?.invalidate()
        
        cancelPendingNotification()
        
        updateLiveActivity()
        updateWidgetState()
        
        syncToWatch(action: "pause")
        FocusManager.shared.disableFocusMode()
    }
    
    func stopTimer() {
        let finalElapsed = TimerLogic.elapsed(
            paused: pausedElapsedTime,
            segmentStartedAt: isRunning ? sessionStartTime : nil
        )
        elapsedTime = finalElapsed
        pausedElapsedTime = finalElapsed
        isRunning = false
        timer?.invalidate()
        
        cancelPendingNotification()
        
        if let session = currentSession { session.duration = finalElapsed }
        FocusManager.shared.disableFocusMode()
        
        endLiveActivity()
        updateWidgetState()
        syncToWatch(action: "stop")
        showEndPageInput = true
    }
    
    func commitSession(to book: Book, context: ModelContext) {
        if let session = currentSession {
            book.addSession(session)
            context.insert(session)
            try? context.save()
        }
        cleanUpAfterFinish()
    }
    
    func cancelSession() {
        FocusManager.shared.disableFocusMode()
        cleanUpAfterFinish()
    }

    func applyRemoteControl(_ action: TimerSyncAction, for book: Book? = nil) {
        switch action {
        case .start:
            if currentSession != nil {
                if !isRunning { resumeTimer() }
            } else if let book {
                startTimer(for: book)
            }
        case .pause:
            if isRunning { pauseTimer() }
        case .stop:
            if isRunning { pauseTimer() }
            endLiveActivity()
        case .cancel:
            if currentSession != nil { cancelSession() }
        case .requestState:
            syncToWatch(action: isRunning ? "start" : "pause")
        }
    }

    func completeSessionFromWatch(bookID: String) {
        guard activeBookID?.uuidString == bookID else { return }
        cleanUpAfterFinish()
    }
    
    private func cleanUpAfterFinish() {
        let lastBookID = activeBookID?.uuidString
        cancelPendingNotification()
        currentSession = nil
        pausedElapsedTime = 0
        elapsedTime = 0
        isRunning = false
        showEndPageInput = false
        activeBookID = nil
        clearWidgetState()
        
        syncToWatch(action: "stop", forcedBookID: lastBookID)
    }
    
    private func startUITimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.elapsedTime = self.pausedElapsedTime + Date().timeIntervalSince(self.sessionStartTime)
                
                if self.isTimerMode, let end = self.timerEndDate, Date() >= end {
                    self.handleTimerCompletion()
                }
            }
        }
    }
    
    private func handleTimerCompletion() {
        timer?.invalidate()
        isRunning = false
        pausedElapsedTime = TimeInterval(targetSeconds)
        elapsedTime = pausedElapsedTime
        
        cancelPendingNotification()
        
        if let session = currentSession { session.duration = pausedElapsedTime }
        FocusManager.shared.disableFocusMode()
        
        updateLiveActivity()
        endLiveActivity()
        triggerEndHapticAndSound()
        showTimerAlert = true
        updateWidgetState()
        syncToWatch(action: "pause")
    }
    
    var formattedTime: String {
        let h = Int(elapsedTime) / 3600
        let m = Int(elapsedTime) / 60 % 60
        let s = Int(elapsedTime) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("Notification permission granted: \(granted)")
        }
    }
    
    func scheduleLocalNotificationIfNeeded() {
        guard isTimerMode, let end = timerEndDate else { return }
        let remainingSeconds = end.timeIntervalSinceNow
        guard remainingSeconds > 0 else { return }
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [TimerLogic.completionNotificationID]
        )
        
        let content = UNMutableNotificationContent()
        content.title = "⏰ Reading Timer Finished!"
        content.body = "You've reached your reading goal for '\(activeBookTitle)'. Great job!"
        content.sound = .default
        content.userInfo = ["type": "timerCompleted"]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remainingSeconds, repeats: false)
        let request = UNNotificationRequest(identifier: TimerLogic.completionNotificationID, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleTimerEndNotification(bookTitle: String, afterMinutes minutes: Int) {
        scheduleLocalNotificationIfNeeded()
    }
    
    func cancelPendingNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [TimerLogic.completionNotificationID]
        )
    }
    
    func triggerEndHapticAndSound() {
        AudioServicesPlaySystemSound(1005)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            generator.notificationOccurred(.warning)
        }
    }
    
    private func getLiveActivityContentState() -> ReadingTimerAttributes.ContentState {
        return ReadingTimerAttributes.ContentState(
            timerStartDate: self.sessionStartTime,
            pausedTime: self.pausedElapsedTime,
            isRunning: self.isRunning,
            isTimerMode: self.isTimerMode,
            targetMinutes: self.targetMinutes,
            timerEndDate: self.isTimerMode ? self.timerEndDate : nil,
            currentPage: self.activeBookCurrentPage,
            totalPages: self.activeBookTotalPages,
            format: self.activeBookFormat
        )
    }
    
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = ReadingTimerAttributes(bookTitle: activeBookTitle, sessionStartTime: sessionStartTime)
        let contentState = getLiveActivityContentState()
        
        do {
            activity = try Activity.request(attributes: attributes, content: ActivityContent(state: contentState, staleDate: nil), pushType: nil)
        } catch { print("❌ Live Activity Error: \(error)") }
    }
    
    private func endLiveActivity() {
        guard let activity = activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }
    
    private func updateLiveActivity() {
        guard let activity = activity else { return }
        let contentState = getLiveActivityContentState()
        Task { await activity.update(ActivityContent(state: contentState, staleDate: nil)) }
    }
    
    private func updateWidgetState() {
        let currentElapsed = isRunning
            ? pausedElapsedTime + Date().timeIntervalSince(sessionStartTime)
            : pausedElapsedTime

        guard let bookID = activeBookID else { return }

        let state = TimerStateManager.TimerState(
            isRunning: isRunning,
            bookTitle: activeBookTitle,
            currentPage: activeBookCurrentPage,
            totalPages: activeBookTotalPages,
            elapsedTime: currentElapsed,
            sessionStartTime: isRunning ? sessionStartTime : nil,
            pausedTime: pausedElapsedTime,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes,
            targetSeconds: targetSeconds,
            timerEndDate: timerEndDate,
            bookID: bookID.uuidString,
            format: activeBookFormat,
            startPage: currentSession?.startPage,
            sessionOriginalStartTime: currentSession?.startTime,
            lastUpdated: Date(),
            sourceDevice: "iphone"
        )

        Task {
            await stateManager.saveStateAsync(state)
        }
    }
    
    private func clearWidgetState() {
        Task {
            TimerStateManager.shared.clearActiveState()
        }
    }
    
    private func restoreStateOnLaunch() {
        if let state = TimerStateManager.shared.loadActiveState(), state.hasActiveSession {
            self.activeBookID = UUID(uuidString: state.bookID ?? "")
            self.activeBookTitle = state.bookTitle
            self.activeBookCurrentPage = state.currentPage
            self.activeBookTotalPages = state.totalPages
            
            self.pausedElapsedTime = state.pausedTime
            self.activeBookFormat = state.format ?? BookFormat.physical.rawValue
            self.isRunning = state.isRunning
            self.isTimerMode = state.isTimerMode
            self.targetSeconds = state.targetSeconds ?? (state.targetMinutes * 60)
            self.timerEndDate = state.timerEndDate

            if state.isRunning, let start = state.sessionStartTime {
                self.sessionStartTime = start
                self.elapsedTime = self.pausedElapsedTime + Date().timeIntervalSince(start)
            } else {
                self.elapsedTime = state.elapsedTime
            }

            let originalStart = state.sessionOriginalStartTime
                ?? state.sessionStartTime
                ?? Date().addingTimeInterval(-state.elapsedTime)
            self.currentSession = ReadingSession(
                startTime: originalStart,
                startPage: state.startPage ?? state.currentPage
            )
            self.currentSession?.duration = state.elapsedTime
            
            if let existingActivity = Activity<ReadingTimerAttributes>.activities.first {
                self.activity = existingActivity
                updateLiveActivity()
            } else if state.isRunning {
                    startLiveActivity()
            }

            if state.isRunning {
                startUITimer()
            }
        } else {
            for activity in Activity<ReadingTimerAttributes>.activities {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }
    
    private func setupTerminationObserver() {
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                if self.currentSession != nil, let bookID = self.activeBookID {
                    let finalElapsed = TimerLogic.elapsed(
                        paused: self.pausedElapsedTime,
                        segmentStartedAt: self.isRunning ? self.sessionStartTime : nil
                    )
                    let state = TimerStateManager.TimerState(
                        isRunning: self.isRunning,
                        bookTitle: self.activeBookTitle,
                        currentPage: self.activeBookCurrentPage,
                        totalPages: self.activeBookTotalPages,
                        elapsedTime: finalElapsed,
                        sessionStartTime: self.isRunning ? self.sessionStartTime : nil,
                        pausedTime: self.isRunning ? self.pausedElapsedTime : finalElapsed,
                        isTimerMode: self.isTimerMode,
                        targetMinutes: self.targetMinutes,
                        targetSeconds: self.targetSeconds,
                        timerEndDate: self.timerEndDate,
                        bookID: bookID.uuidString,
                        format: self.activeBookFormat,
                        startPage: self.currentSession?.startPage,
                        sessionOriginalStartTime: self.currentSession?.startTime
                    )
                    Task { await TimerStateManager.shared.saveStateAsync(state, reloadWidget: true) }
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupReactiveWidgetObservers() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.processPendingWidgetAction()
            }
            .store(in: &cancellables)
    }

    func processPendingWidgetAction() {
        guard let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader"),
              let action = defaults.string(forKey: "widget.action") else { return }

        if action == "toggle", let state = TimerStateManager.shared.loadActiveState() {
            if let actionBookID = defaults.string(forKey: AppGroupKey.widgetActionBookID),
               actionBookID != state.bookID {
                defaults.removeObject(forKey: AppGroupKey.widgetAction)
                defaults.removeObject(forKey: AppGroupKey.widgetActionBookID)
                return
            }
            isRunning = state.isRunning
            pausedElapsedTime = state.pausedTime
            elapsedTime = state.elapsedTime
            if let start = state.sessionStartTime { sessionStartTime = start }

            if isRunning {
                startUITimer()
                FocusManager.shared.enableFocusMode()
                scheduleLocalNotificationIfNeeded()
            } else {
                timer?.invalidate()
                FocusManager.shared.disableFocusMode()
                cancelPendingNotification()
            }
            updateLiveActivity()
            syncToWatch(action: isRunning ? "start" : "pause")
            defaults.removeObject(forKey: AppGroupKey.widgetAction)
            defaults.removeObject(forKey: AppGroupKey.widgetActionBookID)
        } else if action == "stop" {
            stopTimer()
            if defaults.bool(forKey: "widget.openEndPageInput") {
                defaults.removeObject(forKey: "widget.openEndPageInput")
                showEndPageInput = true
            }
            defaults.removeObject(forKey: AppGroupKey.widgetAction)
            defaults.removeObject(forKey: AppGroupKey.widgetActionBookID)
        } else {
            defaults.removeObject(forKey: AppGroupKey.widgetAction)
            defaults.removeObject(forKey: AppGroupKey.widgetActionBookID)
        }
    }
    
    private func syncToWatch(action: String, forcedBookID: String? = nil) {
        let bID = forcedBookID ?? (self.activeBookID?.uuidString ?? "")
        guard !bID.isEmpty else { return }
        
        var payload: [String: Any] = [
            "type": "timerSync",
            "action": action,
            "bookID": bID,
            "isRunning": self.isRunning,
            "elapsedTime": self.elapsedTime,
            "timestamp": Date().timeIntervalSince1970
        ]

        if action != "stop", let state = currentTimerState(), let data = try? JSONEncoder().encode(state) {
            payload["state"] = data
        }
        
        WatchSyncManager.shared.sendTimerSyncToWatch(payload)
    }

    private func currentTimerState() -> TimerStateManager.TimerState? {
        guard let bookID = activeBookID else { return nil }
        let currentElapsed = TimerLogic.elapsed(
            paused: pausedElapsedTime,
            segmentStartedAt: isRunning ? sessionStartTime : nil
        )
        return TimerStateManager.TimerState(
            isRunning: isRunning,
            bookTitle: activeBookTitle,
            currentPage: activeBookCurrentPage,
            totalPages: activeBookTotalPages,
            elapsedTime: currentElapsed,
            sessionStartTime: isRunning ? sessionStartTime : nil,
            pausedTime: pausedElapsedTime,
            isTimerMode: isTimerMode,
            targetMinutes: targetMinutes,
            targetSeconds: targetSeconds,
            timerEndDate: timerEndDate,
            bookID: bookID.uuidString,
            format: activeBookFormat,
            startPage: currentSession?.startPage,
            sessionOriginalStartTime: currentSession?.startTime,
            lastUpdated: Date(),
            sourceDevice: "iphone"
        )
    }
}
