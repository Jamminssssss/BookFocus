import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject private var timerViewModel = TimerViewModel.shared
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var books: [TimerStateManager.BookData] = []
    @State private var selectedBook: TimerStateManager.BookData?
    
    @State private var isColdLoading = true
    @State private var pollingCancellable: AnyCancellable?
    
    private let inkColor = Color.white
    
    var body: some View {
        NavigationStack {
            Group {
                if isColdLoading && books.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView().tint(inkColor)
                        Text("loading...")
                            .font(.custom("ChalkboardSE-Regular", size: 14))
                            .foregroundColor(inkColor.opacity(0.7))
                    }
                } else if books.isEmpty {
                    emptyStateView
                } else {
                    bookListView
                }
            }
            .navigationTitle("books.")
            .task {
                await performColdLaunchSafeSetup()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(newPhase: newPhase)
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .fullScreenCover(item: $selectedBook) { book in
                EndPageInputView(
                    book: book,
                    elapsedTime: timerViewModel.getElapsedTime(for: book.id)
                ) { updatedBook in
                    handleBookUpdate(updatedBook)
                }
            }
        }
    }
    
    // MARK: - Empty State (아날로그 감성)
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(inkColor.opacity(0.5))
            Text("no books.")
                .font(.custom("ChalkboardSE-Bold", size: 18))
                .foregroundStyle(inkColor)
            Text("add books from the iPhone app.")
                .font(.custom("ChalkboardSE-Regular", size: 14))
                .foregroundColor(inkColor.opacity(0.7))
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
                        timerViewModel.prepareForCompletion(bookID: book.id)
                        selectedBook = book
                    }
                )
                .listRowBackground(Color.clear) // 리스트 배경색 투명화
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - 🚀 Cold-Launch Safe Setup
    @MainActor
    private func performColdLaunchSafeSetup() async {
        _ = await WatchDueReminderScheduler.requestAuthorizationIfNeeded()
        await fetchBooksFromDiskOffMainThread()
        
        withAnimation {
            self.isColdLoading = false
        }
        startPolling()
    }
    
    private func fetchBooksFromDiskOffMainThread() async {
        let loadedBooks: [TimerStateManager.BookData] = await Task.detached(priority: .userInitiated) {
            guard let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader"),
                  let data = defaults.data(forKey: "books.data"),
                  let decoded = try? JSONDecoder().decode([TimerStateManager.BookData].self, from: data),
                  !decoded.isEmpty else {
                return await TimerStateManager.shared.loadBooks()
            }
            return decoded
        }.value
        
        if loadedBooks != self.books {
            self.books = loadedBooks
            TimerStateManager.shared.saveBooks(loadedBooks)
            timerViewModel.refreshFromDisk()
        }
    }
    
    // MARK: - Polling Timer Lifecycle
    private func startPolling() {
        stopPolling()
        pollingCancellable = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                guard scenePhase == .active else { return }
                timerViewModel.processPendingWidgetAction()
                Task { await fetchBooksFromDiskOffMainThread() }
            }
    }
    
    private func stopPolling() {
        pollingCancellable?.cancel()
        pollingCancellable = nil
    }
    
    // MARK: - Handlers
    private func handleBookUpdate(_ updatedBook: TimerStateManager.BookData) {
        if let index = books.firstIndex(where: { $0.id == updatedBook.id }) {
            books[index] = updatedBook
        }
        timerViewModel.stopTimer(for: updatedBook.id)
        selectedBook = nil
        
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await fetchBooksFromDiskOffMainThread()
        }
    }
    
    private func handleScenePhaseChange(newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            startPolling()
            timerViewModel.processPendingWidgetAction()
            Task { await fetchBooksFromDiskOffMainThread() }
        case .background, .inactive:
            stopPolling()
        @unknown default: break
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "bookfocus" || url.scheme == "focusreader" else { return }
        timerViewModel.processPendingWidgetAction()
        print("⌚️ Opened via widget deep link: \(url)")
    }
}
