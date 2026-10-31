import SwiftUI
import SwiftData

/// A bookmark-sized task: save a position without creating a timed session.
struct PageProgressInputView: View {
    let book: Book

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var timerManager = ReadingTimerManager.shared
    @State private var pageText = ""
    @State private var showSaveError = false
    @FocusState private var isPageFocused: Bool

    private var paperColor: Color { themeManager.currentTheme.paperColor(isDark: colorScheme == .dark) }
    private var inkColor: Color { themeManager.currentTheme.inkColor(isDark: colorScheme == .dark) }
    private var enteredPage: Int? { Int(pageText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var isValidPage: Bool {
        guard let page = enteredPage else { return false }
        return page >= 0 && page <= book.totalPages
    }
    private var hasActiveTimer: Bool {
        if timerManager.activeBookID == book.id && timerManager.currentSession != nil { return true }
        return TimerStateManager.shared.loadState(forBookID: book.id.uuidString)?.hasActiveSession == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "bookmark")
                    Text(LocalizedStringKey(book.isEbook ? "log progress." : "log page."))
                        .font(.custom("ChalkboardSE-Bold", size: 22))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("cancel")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.custom("ChalkboardSE-Bold", size: 18))
                        .lineLimit(2)
                    Text("Save where you left off without a timer.")
                        .font(.custom("ChalkboardSE-Regular", size: 14))
                        .foregroundStyle(inkColor.opacity(0.65))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringKey(book.isEbook ? "progress (%)" : "last page read"))
                        .font(.custom("ChalkboardSE-Regular", size: 14))
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        TextField(String(book.currentPage), text: $pageText)
                            .font(.custom("ChalkboardSE-Bold", size: 28))
                            .keyboardType(.numberPad)
                            .focused($isPageFocused)
                            .accessibilityLabel(Text(LocalizedStringKey(book.isEbook ? "progress (%)" : "last page read")))
                        Text(book.isEbook ? "%" : "/ \(book.totalPages)")
                            .font(.custom("ChalkboardSE-Regular", size: 18))
                            .foregroundStyle(inkColor.opacity(0.6))
                    }
                }
                .padding(16)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))

                Group {
                    if hasActiveTimer {
                        Text("Finish this book's timer session before updating your place.")
                    } else if !pageText.isEmpty && !isValidPage {
                        Text("Enter a number from 0 to \(book.totalPages).")
                    } else {
                        Text(LocalizedStringKey(book.isEbook ? "Only your progress is saved." : "Only your page is saved."))
                    }
                }
                .font(.custom("ChalkboardSE-Regular", size: 14))
                .foregroundStyle(inkColor.opacity(0.65))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: saveProgress) {
                Label("save place.", systemImage: "bookmark.fill")
                    .font(.custom("ChalkboardSE-Bold", size: 16))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: 25).stroke(inkColor, lineWidth: 1.5))
                    .opacity(isValidPage && !hasActiveTimer ? 1 : 0.35)
            }
            .disabled(!isValidPage || hasActiveTimer)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .background(paperColor)
        }
        .foregroundStyle(inkColor)
        .tint(inkColor)
        .background(paperColor.ignoresSafeArea())
        .presentationDetents([.height(390), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(paperColor)
        .alert("Couldn't save your place.", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again. Your previous place is still saved.")
        }
        .task {
            if !hasActiveTimer { isPageFocused = true }
        }
    }

    private func saveProgress() {
        guard isValidPage, let page = enteredPage, !hasActiveTimer else { return }
        do {
            try book.saveReadingProgress(page, in: modelContext)
            WatchSyncManager.shared.sendBooksToWatch([TimerStateManager.BookData.from(book)])
            dismiss()
        } catch {
            showSaveError = true
        }
    }
}
