import SwiftUI
import SwiftData

// MARK: - Book List View
struct BookListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]

    @State private var showAddBook = false
    
    // 딥링크 처리
    @State private var showEndPageInput = false
    @State private var selectedBook: Book?
    @State private var currentSession: ReadingSession?
    
    // ✅ Premium Gate
    @StateObject private var storeManager = StoreKitManager.shared
    @State private var showPremiumSheet = false
    
    // ✅ App Open Ad Manager
    @StateObject private var appOpenAdManager = AppOpenAdManager.shared
    
    // ✅ 앱 실행 시 첫 광고 표시 여부 추적
    @State private var hasShownInitialAd = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isIPad: Bool { horizontalSizeClass == .regular }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                AdaptiveTopBannerView()
                
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(.systemBackground),
                            Color(.systemGray6).opacity(0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    if books.isEmpty {
                        emptyStateView
                    } else {
                        List {
                            ForEach(books) { book in
                                BookRowView(
                                    book: book,
                                    isIPad: isIPad,
                                    modelContext: modelContext
                                )
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                                .listRowBackground(Color.clear)
                            }
                            .onDelete(perform: deleteBooks)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }

                // 🔽 하단 배너 광고
                AdaptiveBottomBannerView()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        handleAddBookTap()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .fullScreenCover(isPresented: $showAddBook) {
                AddBookView()
            }
            .sheet(isPresented: $showPremiumSheet) {
                PurchaseView()
            }
            .fullScreenCover(isPresented: $showEndPageInput) {
                if let book = selectedBook {
                    EndPageInputView(book: book, session: currentSession) {
                        handleEndPageSaved()
                    } onCancel: {
                        handleEndPageCancelled()
                    }
                }
            }
            .onAppear {
                print("📱 북 리스트 onAppear - 워치 동기화 시작")
                
                // ModelContext를 WatchSyncManager에 설정
                WatchSyncManager.shared.modelContext = modelContext
                
                // ✅ AppGroup 세션 즉시 처리
                WatchSyncManager.shared.processPendingSessions()
                
                // ⌚️ 워치에 모든 책 동기화 (앱 실행 시)
                syncAllBooksToWatch()
                
                // 딥링크 알림 감지
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("OpenEndPageInputFromDeepLink"),
                    object: nil,
                    queue: .main
                ) { _ in
                    handleDeepLinkStop()
                }
                
                // 앱이 포그라운드로 올 때 위젯 스탑 액션 체크
                checkWidgetStopAction()
                
                // 워치 액션 체크
                checkWatchAction()
            }
            .onChange(of: books.count) { oldCount, newCount in
                // 책 개수가 변경되면 워치에 동기화
                if newCount != oldCount {
                    print("📚 책 개수 변경: \(oldCount) -> \(newCount), 워치에 동기화")
                    syncAllBooksToWatch()
                }
            }
            .onChange(of: books.map { $0.id }) { oldIDs, newIDs in
                // 책 ID 목록이 변경되면 워치에 동기화
                if oldIDs != newIDs {
                    print("📚 책 목록 변경, 워치에 동기화")
                    syncAllBooksToWatch()
                }
            }
            .onChange(of: books.map { "\($0.id)-\($0.currentPage)-\($0.lastUpdated)" }) { oldData, newData in
                // 책 페이지나 업데이트 시간이 변경되면 워치에 동기화
                if oldData != newData {
                    print("📚 책 데이터 변경, 워치에 동기화")
                    syncAllBooksToWatch()
                }
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .background {
                    // EndPageInputView가 표시되지 않았고 진행 중 타이머가 아니라면 위젯 상태를 안전하게 정리
                    if !showEndPageInput {
                        let manager = TimerStateManager.shared
                        if let state = manager.loadState(), state.isRunning == false {
                            manager.clearState()
                            // 라이브 액티비티 종료 알림 브로드캐스트 (ReadingTimerView에서 수신)
                            NotificationCenter.default.post(name: Notification.Name("ReadingTimer.EndLiveActivity"), object: nil)
                        }
                    }
                }
                
                if oldPhase == .background && newPhase == .active {
                    print("📱 앱이 포그라운드로 복귀 - 워치 동기화")
                    
                    // ✅ 앱이 백그라운드에서 포그라운드로 올 때
                    
                    // AppGroup 세션 처리
                    WatchSyncManager.shared.processPendingSessions()
                    
                    // 위젯 스탑 액션 체크
                    checkWidgetStopAction()
                    
                    // 워치 액션 체크
                    checkWatchAction()
                    
                    // ⌚️ 워치 동기화 (포그라운드 복귀 시)
                    syncAllBooksToWatch()
                    
                    // ✅ 광고 표시 (약간의 딜레이)
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3초
                        await appOpenAdManager.showAdIfAvailable()
                    }
                }
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(self)
            }
            // ✅ 앱 시작 시 광고 로드
            .task {
                await appOpenAdManager.loadAd()
                
                // 첫 실행 시에만 광고 표시 (쿨타임 체크 포함)
                if !hasShownInitialAd {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5초 대기
                    await appOpenAdManager.showAdIfAvailable()
                    hasShownInitialAd = true
                }
            }
        }
    }
    
    // MARK: - Add Book Logic (Premium Gate)
    private func handleAddBookTap() {
        // 프리미엄 사용자는 무제한 추가 가능
        if storeManager.isPremium {
            showAddBook = true
            return
        }
        
        // 무료 사용자는 1권까지만 추가 가능
        if books.count >= 1 {
            showPremiumSheet = true
        } else {
            showAddBook = true
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: isIPad ? 120 : 80))
                .foregroundStyle(.blue.opacity(0.5))

            Text("empty_no_books_title")
                .font(isIPad ? .largeTitle : .title)
                .fontWeight(.bold)

            Text("empty_no_books_subtitle")
                .foregroundColor(.secondary)
        }
        .padding(40)
    }

    // MARK: - Delete Books
    private func deleteBooks(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let book = books[index]
                book.sessions?.forEach { modelContext.delete($0) }
                book.memos?.forEach { modelContext.delete($0) }
                modelContext.delete(book)
            }
            try? modelContext.save()
            
            // 📚 책 삭제 후 워치 동기화
            syncAllBooksToWatch()
        }
    }
    
    // MARK: - Deep Link Handling
    private func handleDeepLinkStop() {
        checkWidgetStopAction()
    }
    
    private func checkWidgetStopAction() {
        // 이미 EndPageInputView가 표시되어 있으면 무시
        guard !showEndPageInput else { return }
        
        let manager = TimerStateManager.shared
        guard let state = manager.loadState(),
              let bookIDString = state.bookID,
              let bookID = UUID(uuidString: bookIDString) else {
            return
        }
        
        // 위젯에서 스탑 액션이 있는지 체크
        if let defaults = UserDefaults(suiteName: "group.com.Jaemin.FocusReader"),
           defaults.bool(forKey: "widget.openEndPageInput") {
            
            // 플래그 제거
            defaults.removeObject(forKey: "widget.openEndPageInput")
            defaults.removeObject(forKey: "widget.action")
            defaults.synchronize()
            
            // 책 찾기
            guard let book = books.first(where: { $0.id == bookID }) else {
                print("❌ 딥링크: 책을 찾을 수 없음 (ID: \(bookIDString))")
                return
            }
            
            // 세션 생성
            let session = ReadingSession(
                startTime: state.sessionStartTime ?? Date().addingTimeInterval(-state.elapsedTime),
                startPage: book.currentPage
            )
            session.duration = state.elapsedTime
            
            selectedBook = book
            currentSession = session
            showEndPageInput = true
        }
    }
    
    private func handleEndPageSaved() {
        TimerStateManager.shared.clearState()
        selectedBook = nil
        currentSession = nil
        showEndPageInput = false
        
        // 📚 세션 저장 후 워치 동기화
        syncAllBooksToWatch()
    }
    
    private func handleEndPageCancelled() {
        TimerStateManager.shared.clearState()
        selectedBook = nil
        currentSession = nil
        showEndPageInput = false
    }
    
    // MARK: - Watch Sync
    private func syncAllBooksToWatch() {
        let bookDataList = books.map { book in
            TimerStateManager.BookData(
                id: book.id.uuidString,
                title: book.title,
                author: book.author,
                totalPages: book.totalPages,
                currentPage: book.currentPage,
                createdAt: book.createdAt,
                lastUpdated: book.lastUpdated
            )
        }
        // WatchSyncManager를 통해 워치에 전송 (내부에서 AppGroup도 저장)
        WatchSyncManager.shared.sendBooksToWatch(bookDataList)
        print("✅ 워치에 \(bookDataList.count)권의 책 동기화 완료")
    }
    
    private func checkWatchAction() {
        let manager = TimerStateManager.shared
        if let action = manager.getAction() {
            // 워치에서 세션이 저장되었을 때
            if action == "sessionSaved" {
                // 모든 책 다시 동기화
                syncAllBooksToWatch()
                // 대기 중인 세션 처리 (WatchSyncManager가 처리)
                WatchSyncManager.shared.processPendingSessions()
            }
        }
    }
}


// MARK: - Book Row View
struct BookRowView: View {
    let book: Book
    let isIPad: Bool
    let modelContext: ModelContext
    
    @State private var showMemoSheet = false
    @State private var showRereadSheet = false
    @State private var navigateToTimer = false
    
    private var hasMemos: Bool {
        guard let memos = book.memos else { return false }
        return !memos.isEmpty
    }
    
    private var isCompleted: Bool {
        book.currentPage >= book.totalPages
    }
    
    private var coverSize: CGSize {
        isIPad
        ? CGSize(width: 100, height: 140)
        : CGSize(width: 70, height: 100)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // 책 표지 이미지
            coverImageView
                .contentShape(Rectangle())
                .onTapGesture {
                    if hasMemos {
                        showMemoSheet = true
                    } else {
                        // 메모가 없으면 일반 탭과 동일하게 동작
                        handleBookTap()
                    }
                }
            
            // 책 정보
            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(isIPad ? .title2 : .headline)
                    .fontWeight(.bold)
                    .lineLimit(2)
                
                Text(book.author)
                    .font(isIPad ? .body : .subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    Label(pageText, systemImage: "doc.text.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(totalReadingTime, systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 8) {
                    if isCompleted {
                        Text("finished")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                    
        
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            handleBookTap()
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showMemoSheet) {
            MemoTimelineView(book: book)
        }
        .sheet(isPresented: $showRereadSheet) {
            RereadStartPageSheet(book: book, isPresented: $showRereadSheet)
        }
        .onChange(of: showRereadSheet) { _, newValue in
            // 시트가 닫혔을 때 navigateToTimer 리셋
            if !newValue {
                navigateToTimer = false
            }
        }
        .navigationDestination(isPresented: $navigateToTimer) {
            ReadingTimerView(book: book)
        }
    }
    
    // MARK: - Handle Book Tap
    private func handleBookTap() {
        if isCompleted {
            // 완독한 책은 시트만 표시
            showRereadSheet = true
        } else {
            // 읽는 중인 책은 타이머로 이동
            navigateToTimer = true
        }
    }
    
    // MARK: - Cover Image
    private var coverImageView: some View {
        Group {
            if let data = book.coverImageData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.system(size: isIPad ? 40 : 28))
                            .foregroundStyle(.white.opacity(0.5))
                    }
            }
        }
        .frame(width: coverSize.width, height: coverSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(hasMemos ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }
    
    // MARK: - Computed Properties
    private var pageText: String {
        let currentPages = book.currentPage
        let totalPages = book.totalPages
        return "\(currentPages) / \(totalPages)"
    }
    
    private var totalReadingTime: String {
        guard let sessions = book.sessions else { return "0m" }
        let totalSeconds = sessions.reduce(0) { $0 + $1.duration }
        let totalMinutes = Int(totalSeconds / 60)
        return formatTime(minutes: totalMinutes)
    }
    
    private func formatTime(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        
        if hours > 0 {
            if mins > 0 {
                return "\(hours)h \(mins)m"
            } else {
                return "\(hours)h"
            }
        } else {
            return "\(mins)m"
        }
    }
}

// MARK: - Reread Start Page Sheet
struct RereadStartPageSheet: View {
    let book: Book
    @Binding var isPresented: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var startPage: Int = 1
    
    private var isIPad: Bool { horizontalSizeClass == .regular }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    Spacer()
                    
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: isIPad ? 80 : 60))
                        .foregroundStyle(.blue)
                    
                    VStack(spacing: 12) {
                        Text("reread_title")
                            .font(isIPad ? .largeTitle : .title)
                            .fontWeight(.bold)
                        
                        Text("reread_subtitle")
                            .font(isIPad ? .title3 : .body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    VStack(spacing: 16) {
                        HStack {
                            Text("start_page_label")
                                .font(.headline)
                            Spacer()
                            Text("\(startPage)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 24)
                        
                        Picker("start_page_picker", selection: $startPage) {
                            ForEach(1...book.totalPages, id: \.self) { page in
                                Text("\(page)").tag(page)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)
                    }
                    .padding(.vertical, 20)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    Button {
                        startReading()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("start_reading")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("cancel") { isPresented = false }
                }
            }
        }
    }
    
    private func startReading() {
        print("📖 다시 읽기 페이지 설정: \(startPage)페이지")
        
        // 📖 페이지 저장 및 상태 업데이트
        book.currentPage = startPage
        book.isCompleted = false
        book.lastUpdated = Date()
        try? modelContext.save()
        
        print("✅ 페이지 저장 완료: \(startPage)페이지")
        
        // ⌚️ 워치로 즉시 동기화
        syncToWatch()
        
        // 🔙 북 리스트로 돌아가기
        isPresented = false
        
        print("🔙 북 리스트로 복귀")
    }
    
    private func syncToWatch() {
        let bookData = TimerStateManager.BookData(
            id: book.id.uuidString,
            title: book.title,
            author: book.author,
            totalPages: book.totalPages,
            currentPage: book.currentPage,
            createdAt: book.createdAt,
            lastUpdated: book.lastUpdated
        )
        WatchSyncManager.shared.sendBooksToWatch([bookData])
        print("⌚️ 워치 동기화 완료: \(book.title) - \(book.currentPage)페이지")
    }
}

