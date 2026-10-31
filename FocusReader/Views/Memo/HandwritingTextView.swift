//
//  HandwritingTextView.swift
//  FocusReader
//
//  Created by JeaminPark on 7/6/26.
//

import SwiftUI
import AudioToolbox

struct HandwritingTextView: View {
    let fullText: String
    let font: Font
    let color: Color
    var speed: Double = 0.06 // ⭐️ 기존(0.035)보다 2배 가까이 여유로운 속도
    var initialDelay: Double = 0.0 // ⭐️ 글자 쓰기를 시작하기 전 대기 시간
    var playSound: Bool = true
    var onComplete: (() -> Void)? = nil
    
    @State private var displayedText: String = ""
    @State private var typingTask: Task<Void, Never>? = nil
    
    var body: some View {
        Text(displayedText)
            .font(font)
            .foregroundColor(color)
            .lineSpacing(6)
            .onAppear {
                startHandwriting()
            }
            .onChange(of: fullText) {
                startHandwriting()
            }
            .onDisappear {
                typingTask?.cancel()
            }
    }
    
    private func startHandwriting() {
        typingTask?.cancel()
        displayedText = ""
        
        typingTask = Task { @MainActor in
            // ⭐️ 1. 시작 전 설정된 시간(초)만큼 여유롭게 숨고르기 대기
            if initialDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            }
            
            for char in fullText {
                if Task.isCancelled { break }
                
                displayedText.append(char)
                
                if playSound && !char.isWhitespace {
                    playWritingSound()
                }
                
                // ⭐️ 2. 실제 손글씨처럼 미세한 리듬감 부여
                let randomDelay = max(0.02, speed + Double.random(in: -0.02...0.02))
                try? await Task.sleep(nanoseconds: UInt64(randomDelay * 1_000_000_000))
            }
            
            if !Task.isCancelled {
                onComplete?()
            }
        }
    }
    
    private func playWritingSound() {
        AudioServicesPlaySystemSound(1104)
    }
}
