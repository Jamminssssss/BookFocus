//
//  ReadingTimerView.swift
//  FocusReader
//
//  Created by JeaminPark on 12/10/25.
//

import SwiftUI
import SwiftData
import UserNotifications

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
    @State private var isDoNotDisturbEnabled: Bool = false
    @State private var showMemoTimeline: Bool = false
    
    var body: some View {
        VStack {
            Spacer()
            
            // 책 정보 (일러스트)
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
            
            // 타이머 표시 (중앙)
            VStack(spacing: 20) {
                Text(formatTime(elapsedTime))
                    .font(.system(size: 60, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                
                Text("Current Page: \(book.currentPage) / \(book.totalPages)")
                    .font(.headline)
            }
            .padding(.vertical, 40)
            
            // 방해 금지 모드 토글
            Toggle(isOn: $isDoNotDisturbEnabled) {
                Label("Do Not Disturb", systemImage: isDoNotDisturbEnabled ? "moon.fill" : "moon")
                    .font(.headline)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 10)
            .onChange(of: isDoNotDisturbEnabled) { oldValue, newValue in
                toggleDoNotDisturb(enabled: newValue)
            }
            
            // 컨트롤 버튼
            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    Button(action: startTimer) {
                        Label("Screenshot", systemImage: "camera.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    
                    Button(action: { showMemoTimeline = true }) {
                        Label("View Memos", systemImage: "note.text")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.purple)
                            .cornerRadius(10)
                    }
                }
                
                HStack(spacing: 20) {
                    Button(action: pauseTimer) {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.orange)
                            .cornerRadius(10)
                    }
                    .disabled(!isRunning)
                    .opacity(isRunning ? 1 : 0.5)
                    
                    Button(action: stopTimer) {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                    .disabled(!isRunning)
                    .opacity(isRunning ? 1 : 0.5)
                }
            }
            .padding(.top, 20)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Reading Timer")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEndPageInput) {
            EndPageInputView(
                book: book,
                session: currentSession,
                onComplete: {
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showMemoTimeline) {
            MemoTimelineView(book: book)
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startTimer() {
        if currentSession == nil {
            // 새 세션 생성
            let now = Date()
            let session = ReadingSession(
                startTime: now,
                startPage: book.currentPage,
                book: book
            )
            modelContext.insert(session)
            
            // Book의 sessions에 추가
            if book.sessions == nil {
                book.sessions = []
            }
            book.sessions?.append(session)
            
            currentSession = session
            sessionStartTime = now
            pausedElapsedTime = 0
            elapsedTime = 0
        } else {
            // 재개: 일시정지된 시간부터 계속
            sessionStartTime = Date() - pausedElapsedTime
        }
        
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedTime = Date().timeIntervalSince(sessionStartTime)
        }
    }
    
    private func pauseTimer() {
        isRunning = false
        pausedElapsedTime = elapsedTime
        timer?.invalidate()
    }
    
    private func stopTimer() {
        isRunning = false
        timer?.invalidate()
        
        // 현재까지의 경과 시간을 저장
        if let session = currentSession {
            // 세션의 실제 시작 시간을 기준으로 경과 시간 계산
            let actualElapsed = Date().timeIntervalSince(session.startTime)
            session.duration = actualElapsed
        }
        
        showEndPageInput = true
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private func toggleDoNotDisturb(enabled: Bool) {
        if enabled {
            // 방해 금지 모드 활성화
            UNUserNotificationCenter.current().requestAuthorization(options: []) { granted, _ in
                if granted {
                    // 알림 설정을 변경할 수는 없지만, 상태만 표시
                    // 실제로는 시스템 설정에서 방해 금지 모드를 켜도록 안내할 수 있음
                }
            }
        }
    }
}

