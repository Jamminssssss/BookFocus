// BookRowView+WidgetSync.swift
// ─────────────────────────────────────────────────────────────────────────────
// Watch App target ONLY.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

struct BookRowView: View {
    let book: TimerStateManager.BookData
    @ObservedObject var timerViewModel: TimerViewModel
    let onStop: () -> Void

    private let inkColor = Color.white // WatchOS 특성상 다크모드 베이스
    
    private var elapsedTime: TimeInterval {
        timerViewModel.getElapsedTime(for: book.id)
    }

    private var isRunning: Bool {
        timerViewModel.isRunning(for: book.id)
    }

    private var canStart: Bool {
        timerViewModel.canStartSession(for: book.id)
    }

    private var progressFraction: Double {
        guard book.totalPages > 0 else { return 0 }
        return min(Double(book.currentPage) / Double(book.totalPages), 1.0)
    }

    private var dueDaysRemaining: Int? {
        guard let due = book.dueDate else { return nil }
        return Calendar.current.dateComponents([.day], from: .now, to: due).day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── 제목 + 마감 및 상태 뱃지 ──────────────────────────────────────────────
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.custom("ChalkboardSE-Bold", size: 16))
                        .foregroundStyle(inkColor)
                        .lineLimit(2)
                    
                    if !book.author.isEmpty {
                        Text(book.author)
                            .font(.custom("ChalkboardSE-Regular", size: 12))
                            .foregroundStyle(inkColor.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                Spacer()
                
                // 🔥 [핵심 수정]: 반납/재대출 상태 우선 표시 -> 일반 대출 중일 때만 마감일 계산
                if book.isReturned {
                    StatusBadge(text: "returned", color: .white.opacity(0.5))
                } else if book.isRenewed {
                    StatusBadge(text: "renewed", color: .green.opacity(0.8))
                } else if let days = dueDaysRemaining {
                    DueBadge(daysRemaining: days)
                }
            }

            // ── 진행률 바 (스케치 스타일) ─────────────────────────────────────────
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(inkColor.opacity(0.3), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(inkColor.opacity(0.8))
                        .frame(width: geo.size.width * progressFraction)
                }
            }
            .frame(height: 6)

            // ── 페이지 + 타이머 ───────────────────────────────────────────────
            HStack {
                if book.isEbook {
                    Text("\((Double(book.currentPage) / 100).formatted(.percent.precision(.fractionLength(0))))")
                        .font(.custom("ChalkboardSE-Regular", size: 12))
                        .foregroundColor(inkColor.opacity(0.7))
                } else {
                    Text("p. \(book.currentPage) / \(book.totalPages)")
                        .font(.custom("ChalkboardSE-Regular", size: 12))
                        .foregroundColor(inkColor.opacity(0.7))
                }
                
                Spacer()
                let _ = timerViewModel.tick
                Text(elapsedTime.formattedTimer)
                    .font(.custom("ChalkboardSE-Bold", size: 14))
                    .foregroundColor(isRunning ? inkColor : inkColor.opacity(0.7))
            }

            // ── 컨트롤 버튼 (채우기 없이 테두리만) ──────────────────────────────────
            HStack(spacing: 8) {
                Button {
                    if isRunning {
                        timerViewModel.pauseTimer(for: book.id)
                    } else {
                        timerViewModel.startOrResumeTimer(for: book)
                    }
                } label: {
                    Image(systemName: isRunning ? "pause" : "play")
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(inkColor, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(inkColor)
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.3)

                Button(action: onStop) {
                    Image(systemName: "stop")
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(inkColor, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(inkColor)
                .disabled(!isRunning && elapsedTime == 0)
                .opacity((!isRunning && elapsedTime == 0) ? 0.3 : 1.0)
            }
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(inkColor, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
        )
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge (반납/재대출 상태 뱃지)
private struct StatusBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.custom("ChalkboardSE-Regular", size: 10))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(color, lineWidth: 1.2))
    }
}

// MARK: - Due Date Badge (아날로그 스타일)
private struct DueBadge: View {
    let daysRemaining: Int

    private var label: String {
        if daysRemaining < 0  { return "overdue" }
        if daysRemaining == 0 { return "due today" }
        if daysRemaining == 1 { return "due tmrw" }
        return "due \(daysRemaining)d"
    }

    private var color: Color {
        if daysRemaining < 0  { return .red }
        if daysRemaining <= 1 { return .orange }
        return .white.opacity(0.7)
    }

    var body: some View {
        Text(label)
            .font(.custom("ChalkboardSE-Regular", size: 10))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(color, lineWidth: 1.2))
    }
}

// MARK: - TimeInterval helper
private extension TimeInterval {
    var formattedTimer: String {
        let total = Int(self)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
