//
//  TimerView.swift
//  BookFocus Watch Watch App
//
//  Timer control view for watch
//

import SwiftUI

struct TimerView: View {
    let book: TimerStateManager.BookData
    @Environment(\.dismiss) private var dismiss
    
    @State private var timerState: TimerStateManager.TimerState?
    @State private var elapsedTime: TimeInterval = 0
    @State private var isRunning: Bool = false
    @State private var timer: Timer?
    @State private var showEndPageInput = false
    
    var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        // Book information
                        VStack(spacing: 4) {
                            Text(book.title)
                                .font(.headline)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            
                            Text("\(book.currentPage) / \(book.totalPages) pages")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                        
                        // Elapsed time
                        Text(formatTime(elapsedTime))
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundColor(isRunning ? .primary : .secondary)
                        
                        // Buttons
                        VStack(spacing: 8) {
                            // Play/Pause
                            Button {
                                toggleTimer()
                            } label: {
                                HStack {
                                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                                        .font(.title3)
                                    Text(isRunning ? "Pause" : "Play")
                                        .font(.body)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(isRunning ? Color.orange : Color.green)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.borderless)
                            
                            // Stop
                            Button {
                                stopTimer()
                            } label: {
                                HStack {
                                    Image(systemName: "stop.fill")
                                        .font(.title3)
                                    Text("Stop")
                                        .font(.body)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.borderless)
                            .disabled(!isRunning && elapsedTime == 0)
                            .opacity((!isRunning && elapsedTime == 0) ? 0.5 : 1.0)
                        }
                    }
                    .padding()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
            }
        .sheet(isPresented: $showEndPageInput) {
            EndPageInputView(book: book, elapsedTime: elapsedTime)
        }
        .onAppear {
            loadState()
            startUITimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onChange(of: showEndPageInput) { oldValue, newValue in
            // EndPageInputView가 닫힐 때 상태 다시 로드
            if oldValue == true && newValue == false {
                // 상태를 완전히 초기화
                timerState = nil
                isRunning = false
                elapsedTime = 0
                timer?.invalidate()
                
                // 저장된 상태 다시 확인
                loadState()
            }
        }
    }
    
    private func loadState() {
        let manager = TimerStateManager.shared
        if let state = manager.loadState(), state.bookID == book.id {
            timerState = state
            isRunning = state.isRunning
            elapsedTime = state.elapsedTime
            
            if state.isRunning, let startDate = state.sessionStartTime {
                let now = Date()
                elapsedTime = state.pausedTime + now.timeIntervalSince(startDate)
            } else {
                elapsedTime = state.pausedTime
            }
        } else {
            // 새 세션 시작 준비 또는 초기화된 상태
            timerState = nil
            isRunning = false
            elapsedTime = 0
        }
    }
    
    private func toggleTimer() {
        if isRunning {
            pauseTimer()
        } else {
            if timerState == nil {
                startTimer()
            } else {
                resumeTimer()
            }
        }
    }
    
    private func startTimer() {
        let now = Date()
        isRunning = true
        
        let state = TimerStateManager.TimerState(
            isRunning: true,
            bookTitle: book.title,
            currentPage: book.currentPage,
            totalPages: book.totalPages,
            elapsedTime: 0,
            sessionStartTime: now,
            pausedTime: 0,
            isTimerMode: false,
            targetMinutes: 30,
            timerEndDate: nil,
            bookID: book.id
        )
        
        timerState = state
        TimerStateManager.shared.saveState(state)
        TimerStateManager.shared.setAction("start")
        
        startUITimer()
    }
    
    private func resumeTimer() {
        guard var state = timerState else { return }
        
        let now = Date()
        state.sessionStartTime = now
        state.isRunning = true
        state.elapsedTime = elapsedTime
        
        timerState = state
        isRunning = true
        
        TimerStateManager.shared.saveState(state)
        TimerStateManager.shared.setAction("resume")
        
        startUITimer()
    }
    
    private func pauseTimer() {
        guard var state = timerState else { return }
        
        state.pausedTime = elapsedTime
        state.isRunning = false
        state.sessionStartTime = nil
        
        timerState = state
        isRunning = false
        
        timer?.invalidate()
        
        TimerStateManager.shared.saveState(state)
        TimerStateManager.shared.setAction("pause")
    }
    
    private func stopTimer() {
        guard var state = timerState else { return }
        
        state.isRunning = false
        state.pausedTime = elapsedTime
        state.sessionStartTime = nil
        
        timerState = state
        isRunning = false
        
        timer?.invalidate()
        
        TimerStateManager.shared.saveState(state)
        TimerStateManager.shared.setAction("stop")
        
        showEndPageInput = true
    }
    
    private func startUITimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let state = timerState, state.isRunning, let startDate = state.sessionStartTime {
                let now = Date()
                elapsedTime = state.pausedTime + now.timeIntervalSince(startDate)
                
                // 상태 업데이트
                var updatedState = state
                updatedState.elapsedTime = elapsedTime
                TimerStateManager.shared.saveState(updatedState)
            }
        }
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
