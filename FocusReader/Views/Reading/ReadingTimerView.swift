//
//  ReadingTimerView.swift
//  FocusReader
//
//  Created by JeaminPark on 12/10/25.
//

import SwiftUI
import SwiftData

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
            
            // 컨트롤 버튼
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
        .sheet(isPresented: $showEndPageInput) {
            EndPageInputView(
                book: book,
                session: currentSession,
                onComplete: {
                    dismiss()
                }
            )
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func toggleTimer() {
        if isRunning {
            // Pause
            pauseTimer()
        } else {
            // Start or Resume
            if currentSession == nil {
                startTimer()
            } else {
                resumeTimer()
            }
        }
    }
    
    private func startTimer() {
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
        
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedTime = Date().timeIntervalSince(sessionStartTime)
        }
    }
    
    private func resumeTimer() {
        // 재개: 일시정지된 시간부터 계속
        sessionStartTime = Date() - pausedElapsedTime
        
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
}
