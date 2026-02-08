//
//  TimerViewModel.swift
//  BookFocus Watch Watch App
//
//  Manages timer states for all books
//

import Foundation
import Combine

class TimerViewModel: ObservableObject {
    static let shared = TimerViewModel()
    
    // Timer states for each book (key: bookID)
    @Published private var timerStates: [String: TimerState] = [:]
    
    // Active timers for updating elapsed time
    private var activeTimers: [String: Timer] = [:]
    
    private let stateManager = TimerStateManager.shared
    
    struct TimerState {
        var isRunning: Bool
        var elapsedTime: TimeInterval
        var sessionStartTime: Date?
        var pausedTime: TimeInterval
        
        var bookID: String
        var bookTitle: String
        var currentPage: Int
        var totalPages: Int
    }
    
    private init() {
        loadAllTimerStates()
    }
    
    // MARK: - Public Methods
    
    func isRunning(for bookID: String) -> Bool {
        timerStates[bookID]?.isRunning ?? false
    }
    
    func getElapsedTime(for bookID: String) -> TimeInterval {
        guard let state = timerStates[bookID] else { return 0 }
        
        if state.isRunning, let startTime = state.sessionStartTime {
            return state.pausedTime + Date().timeIntervalSince(startTime)
        } else {
            return state.pausedTime
        }
    }
    
    func startOrResumeTimer(for book: TimerStateManager.BookData) {
        let bookID = book.id
        
        if timerStates[bookID] != nil {
            // Resume existing timer
            resumeTimer(for: bookID)
        } else {
            // Start new timer
            startTimer(for: book)
        }
    }
    
    func pauseTimer(for bookID: String) {
        guard var state = timerStates[bookID], state.isRunning else { return }
        
        // Calculate elapsed time
        if let startTime = state.sessionStartTime {
            state.pausedTime += Date().timeIntervalSince(startTime)
        }
        
        state.isRunning = false
        state.sessionStartTime = nil
        timerStates[bookID] = state
        
        // Stop UI timer
        activeTimers[bookID]?.invalidate()
        activeTimers[bookID] = nil
        
        // Save state
        saveTimerState(state)
        
        print("⏸ Timer paused for: \(state.bookTitle)")
    }
    
    func stopTimer(for bookID: String) {
        // Clear timer state
        timerStates.removeValue(forKey: bookID)
        activeTimers[bookID]?.invalidate()
        activeTimers.removeValue(forKey: bookID)
        
        // Clear persisted state
        clearPersistedState(for: bookID)
        
        print("⏹ Timer stopped for: \(bookID)")
    }
    
    // MARK: - Private Methods
    
    private func startTimer(for book: TimerStateManager.BookData) {
        let bookID = book.id
        let now = Date()
        
        let state = TimerState(
            isRunning: true,
            elapsedTime: 0,
            sessionStartTime: now,
            pausedTime: 0,
            bookID: bookID,
            bookTitle: book.title,
            currentPage: book.currentPage,
            totalPages: book.totalPages
        )
        
        timerStates[bookID] = state
        startUITimer(for: bookID)
        saveTimerState(state)
        
        print("▶️ Timer started for: \(book.title)")
    }
    
    private func resumeTimer(for bookID: String) {
        guard var state = timerStates[bookID] else { return }
        
        state.isRunning = true
        state.sessionStartTime = Date()
        timerStates[bookID] = state
        
        startUITimer(for: bookID)
        saveTimerState(state)
        
        print("▶️ Timer resumed for: \(state.bookTitle)")
    }
    
    private func startUITimer(for bookID: String) {
        // Stop existing timer if any
        activeTimers[bookID]?.invalidate()
        
        // Create new timer
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Trigger UI update
            self.objectWillChange.send()
            
            // Save state periodically
            if let state = self.timerStates[bookID] {
                self.saveTimerState(state)
            }
        }
        
        activeTimers[bookID] = timer
    }
    
    // MARK: - Persistence
    
    private func loadAllTimerStates() {
        // Load from TimerStateManager if exists
        if let persistedState = stateManager.loadState(),
           let bookID = persistedState.bookID {
            
            let state = TimerState(
                isRunning: persistedState.isRunning,
                elapsedTime: persistedState.elapsedTime,
                sessionStartTime: persistedState.sessionStartTime,
                pausedTime: persistedState.pausedTime,
                bookID: bookID,
                bookTitle: persistedState.bookTitle,
                currentPage: persistedState.currentPage,
                totalPages: persistedState.totalPages
            )
            
            timerStates[bookID] = state
            
            // Restart UI timer if running
            if state.isRunning {
                startUITimer(for: bookID)
            }
            
            print("📥 Loaded timer state for: \(state.bookTitle)")
        }
    }
    
    private func saveTimerState(_ state: TimerState) {
        let managerState = TimerStateManager.TimerState(
            isRunning: state.isRunning,
            bookTitle: state.bookTitle,
            currentPage: state.currentPage,
            totalPages: state.totalPages,
            elapsedTime: getElapsedTime(for: state.bookID),
            sessionStartTime: state.sessionStartTime,
            pausedTime: state.pausedTime,
            isTimerMode: false,
            targetMinutes: 30,
            timerEndDate: nil,
            bookID: state.bookID
        )
        
        stateManager.saveState(managerState)
    }
    
    private func clearPersistedState(for bookID: String) {
        // Only clear if this is the active state
        if let currentState = stateManager.loadState(),
           currentState.bookID == bookID {
            stateManager.clearState()
        }
    }
}
