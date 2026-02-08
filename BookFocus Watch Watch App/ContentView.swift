//
//  ContentView.swift
//  BookFocus Watch Watch App
//
//  Refactored: Timer controls integrated directly in book list
//

import SwiftUI

struct ContentView: View {
    @StateObject private var timerViewModel = TimerViewModel.shared
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var books: [TimerStateManager.BookData] = []
    @State private var refreshTimer: Timer?
    @State private var showEndPageInput = false
    @State private var selectedBook: TimerStateManager.BookData?
    @State private var wasShowingEndPageInput = false
    
    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyStateView
                } else {
                    bookListView
                }
            }
            .navigationTitle("Books")
            .onAppear {
                setupView()
            }
            .onDisappear {
                cleanupView()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
            }
            .onChange(of: showEndPageInput) { oldValue, newValue in
                // Detect when EndPageInputView is dismissed without saving
                if oldValue == true && newValue == false && selectedBook != nil {
                    print("⚠️ EndPageInputView dismissed without saving")
                    if let book = selectedBook {
                        timerViewModel.stopTimer(for: book.id)
                    }
                    selectedBook = nil
                }
            }
            .sheet(isPresented: $showEndPageInput) {
                if let book = selectedBook {
                    EndPageInputView(
                        book: book,
                        elapsedTime: timerViewModel.getElapsedTime(for: book.id)
                    ) { updatedBook in
                        handleBookUpdate(updatedBook)
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("No Books")
                .font(.headline)
            
            Text("Add books from the iPhone app")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Book List
    
    private var bookListView: some View {
        List {
            ForEach(books) { book in
                BookRowView(
                    book: book,
                    timerViewModel: timerViewModel,
                    onStop: {
                        handleStop(for: book)
                    }
                )
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Setup & Cleanup
    
    private func setupView() {
        // Activate WCSession
        _ = WatchSessionManager.shared
        
        // Load books
        loadBooks()
        
        // Start refresh timer
        startRefreshTimer()
    }
    
    private func cleanupView() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func loadBooks() {
        books = TimerStateManager.shared.loadBooks()
        print("📚 Loaded \(books.count) books")
    }
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            loadBooks()
        }
    }
    
    // MARK: - Actions
    
    private func handleStop(for book: TimerStateManager.BookData) {
        selectedBook = book
        showEndPageInput = true
    }
    
    private func handleBookUpdate(_ updatedBook: TimerStateManager.BookData) {
        // Update local book list
        if let index = books.firstIndex(where: { $0.id == updatedBook.id }) {
            books[index] = updatedBook
        }
        
        // Clear timer state for this book
        timerViewModel.stopTimer(for: updatedBook.id)
        
        // Reset selection
        selectedBook = nil
        showEndPageInput = false
        wasShowingEndPageInput = false
        
        // Reload books to ensure sync
        loadBooks()
        
        print("✅ Book updated: \(updatedBook.title), Page: \(updatedBook.currentPage)")
    }
    
    // MARK: - Scene Phase Handling
    
    private func handleScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) {
        print("🔄 Scene phase changed: \(oldPhase) → \(newPhase)")
        
        // Track if EndPageInputView was showing
        if newPhase == .background || newPhase == .inactive {
            wasShowingEndPageInput = showEndPageInput
            
            if showEndPageInput {
                print("⚠️ App going to background/sleep with EndPageInputView open")
            }
        }
        
        // Reset when returning from background/sleep
        if oldPhase == .background && newPhase == .active {
            print("✅ App returned from background")
            
            // If EndPageInputView was showing, dismiss it and reset timer
            if wasShowingEndPageInput {
                print("🔄 Resetting EndPageInputView and timer after sleep")
                
                if let book = selectedBook {
                    timerViewModel.stopTimer(for: book.id)
                }
                
                showEndPageInput = false
                selectedBook = nil
                wasShowingEndPageInput = false
                
                // Reload books to refresh UI
                loadBooks()
            }
        }
    }
}

// MARK: - Book Row View

struct BookRowView: View {
    let book: TimerStateManager.BookData
    @ObservedObject var timerViewModel: TimerViewModel
    let onStop: () -> Void
    
    private var isRunning: Bool {
        timerViewModel.isRunning(for: book.id)
    }
    
    private var elapsedTime: TimeInterval {
        timerViewModel.getElapsedTime(for: book.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Book Title
            Text(book.title)
                .font(.headline)
                .lineLimit(2)
            
            // Timer Display
            if elapsedTime > 0 || isRunning {
                Text(formatTime(elapsedTime))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(isRunning ? .green : .secondary)
            }
            
            // Control Buttons
            HStack(spacing: 8) {
                // Play/Pause Button
                Button {
                    if isRunning {
                        timerViewModel.pauseTimer(for: book.id)
                    } else {
                        timerViewModel.startOrResumeTimer(for: book)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                            .font(.caption)
                        Text(isRunning ? "Pause" : "Play")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(isRunning ? .orange : .green)
                
                // Stop Button
                Button {
                    onStop()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.caption)
                        Text("Stop")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(!isRunning && elapsedTime == 0)
                .opacity((!isRunning && elapsedTime == 0) ? 0.5 : 1.0)
            }
        }
        .padding(.vertical, 4)
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

#Preview {
    ContentView()
}
