import SwiftUI
import SwiftData

// MARK: - Book List View
struct BookListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]

    @State private var showAddBook = false
    @State private var currentIndex = 0
    @State private var showDetails = false
    
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
                        VStack(spacing: 0) {
                            TabView(selection: $currentIndex) {
                                ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                                    BookCardView(
                                        book: book,
                                        onDelete: { deleteBook(book) },
                                        showDetails: $showDetails,
                                        isIPad: isIPad
                                    )
                                    .tag(index)
                                }
                            }
                            .tabViewStyle(
                                .page(
                                    indexDisplayMode: books.count > 1 ? .automatic : .never
                                )
                            )
                            .onChange(of: currentIndex) { _, _ in
                                showDetails = false
                            }

                            bottomInfoView
                        }
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
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if oldPhase == .background && newPhase == .active {
                    // 앱이 백그라운드에서 포그라운드로 올 때 체크
                    checkWidgetStopAction()
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
            // ✅ Scene Phase 변화 감지 (백그라운드 → 포그라운드 복귀 시)
                       .onChange(of: scenePhase) {
                           // 백그라운드에서 돌아올 때만 광고 표시 (쿨타임 체크 포함)
                           if scenePhase == .active {
                               Task {
                                   // 약간의 딜레이로 자연스러운 전환
                                   try? await Task.sleep(nanoseconds: 300_000_000) // 0.3초
                                   await appOpenAdManager.showAdIfAvailable()
                               }
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

    // MARK: - Bottom Info
    private var bottomInfoView: some View {
        VStack {
            if books.count > 1 {
                Text("\(currentIndex + 1) / \(books.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .background(Color(.systemBackground))
    }

    private func deleteBook(_ book: Book) {
        withAnimation {
            book.sessions?.forEach { modelContext.delete($0) }
            book.memos?.forEach { modelContext.delete($0) }
            modelContext.delete(book)
            try? modelContext.save()
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
    }
    
    private func handleEndPageCancelled() {
        TimerStateManager.shared.clearState()
        selectedBook = nil
        currentSession = nil
        showEndPageInput = false
    }
}


// MARK: - Book Card View
struct BookCardView: View {
    let book: Book
    let onDelete: () -> Void
    @Binding var showDetails: Bool
    let isIPad: Bool
    
    @State private var showInfoOverlay = false
    @State private var showRereadSheet = false
    
    private var isCompleted: Bool {
        book.currentPage >= book.totalPages
    }
    
    private var coverSize: CGSize {
        isIPad
        ? CGSize(width: 480, height: 680)
        : CGSize(width: 280, height: 400)
    }
    
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack {
                    Spacer(minLength: 20)
                    
                    bookCoverWithOverlay
                        .offset(y: showDetails ? -12 : 0)
                        .scaleEffect(showDetails ? 1.03 : 1.0)
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.85),
                            value: showDetails
                        )
                        .onTapGesture {
                            handleTap()
                        }
                    
                    if showDetails {
                        actionButtonsView
                            .padding(.top, isIPad ? 32 : 24)
                            .padding(.bottom, isIPad ? 100 : 80)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Spacer(minLength: 20)
                }
                .frame(minHeight: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .sheet(isPresented: $showRereadSheet) {
            RereadStartPageSheet(book: book, isPresented: $showRereadSheet)
        }
    }
    
    // MARK: - Tap Logic
    private func handleTap() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            showDetails.toggle()
            showInfoOverlay = showDetails
        }
    }
    
    // MARK: - Book Cover + Overlay
    private var bookCoverWithOverlay: some View {
        ZStack {
            coverImage
                .drawingGroup()
            
            if isCompleted && !showDetails {
                completedOverlay
            }
            
            infoOverlay
                .opacity(showInfoOverlay ? 1 : 0)
                .allowsHitTesting(showInfoOverlay)
        }
        .frame(width: coverSize.width, height: coverSize.height)
    }
    
    private var coverImage: some View {
        Group {
            if let data = book.coverImageData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.system(size: isIPad ? 120 : 80))
                            .foregroundStyle(.white.opacity(0.5))
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(
            color: .black.opacity(showDetails ? 0.2 : 0.3),
            radius: showDetails ? 12 : 20,
            y: showDetails ? 6 : 10
        )
    }
    
    // MARK: - Info Overlay
    private var infoOverlay: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.black.opacity(0.8))
            .overlay {
                VStack(spacing: 18) {
                    // Title
                    HStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.9))
                        
                        Text(book.title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Author
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(book.author)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.3))
                        .padding(.horizontal, 20)
                    
                    // Pages
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(pageText)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    // Reading Time
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text(totalReadingTime)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .padding(24)
            }
    }
    
    // MARK: - Completed Overlay
    private var completedOverlay: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.clear)
            .overlay {
                Text("finished")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
    }
    
    // MARK: - Action Buttons
    private var actionButtonsView: some View {
        HStack(spacing: 14) {
            if isCompleted {
                Button {
                    showRereadSheet = true
                } label: {
                    ActionButton(
                        icon: "arrow.clockwise",
                        title: "action_reread",
                        role: nil,
                        isIPad: isIPad
                    )
                }
            } else {
                NavigationLink(destination: ReadingTimerView(book: book)) {
                    ActionButton(
                        icon: "play.fill",
                        title: "action_read",
                        role: nil,
                        isIPad: isIPad
                    )
                }
            }
            
            NavigationLink(destination: MemoTimelineView(book: book)) {
                ActionButton(
                    icon: "square.and.pencil",
                    title: "action_memos",
                    role: nil,
                    isIPad: isIPad
                )
            }
            
            Button(role: .destructive, action: onDelete) {
                ActionButton(
                    icon: "trash",
                    title: "action_delete",
                    role: .destructive,
                    isIPad: isIPad
                )
            }
        }
    }
    
    // MARK: - Computed Properties
    private var pageText: String {
        let currentPages = book.currentPage
        let totalPages = book.totalPages
        let pageUnitKey = totalPages == 1 ? "page_singular" : "page_plural"
        let pageUnit = NSLocalizedString(pageUnitKey, comment: "Page unit")
        
        return String(format: "%d / %d %@", currentPages, totalPages, pageUnit)
    }
    
    private var totalReadingTime: String {
        guard let sessions = book.sessions else { return formatTime(minutes: 0) }
        let totalSeconds = sessions.reduce(0) { $0 + $1.duration }
        let totalMinutes = Int(totalSeconds / 60)
        return formatTime(minutes: totalMinutes)
    }
    
    private func formatTime(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        
        let hourUnit = NSLocalizedString(hours == 1 ? "hour_singular" : "hour_plural", comment: "Hour unit")
        let minUnit = NSLocalizedString(mins == 1 ? "minute_singular" : "minute_plural", comment: "Minute unit")
        
        if hours > 0 {
            if mins > 0 {
                return String(format: "%d%@ %d%@", hours, hourUnit, mins, minUnit)
            } else {
                return String(format: "%d%@", hours, hourUnit)
            }
        } else {
            return String(format: "%d%@", mins, minUnit)
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
    @State private var navigateToTimer = false
    
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
                            Image(systemName: "play.fill")
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
            .navigationDestination(isPresented: $navigateToTimer) {
                ReadingTimerView(book: book)
            }
        }
    }
    
    private func startReading() {
        book.currentPage = startPage
        try? modelContext.save()
        
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            navigateToTimer = true
        }
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let icon: String
    let title: LocalizedStringKey
    let role: ButtonRole?
    let isIPad: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: isIPad ? 20 : 18, weight: .semibold))
            
            Text(title)
                .font(.system(size: isIPad ? 15 : 13, weight: .semibold))
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, isIPad ? 20 : 16)
        .padding(.vertical, isIPad ? 14 : 12)
        .background(backgroundColor)
        .clipShape(Capsule())
    }
    
    private var foregroundColor: Color {
        switch role {
        case .destructive: return .red
        default: return .primary
        }
    }
    
    private var backgroundColor: Color {
        switch role {
        case .destructive: return Color.red.opacity(0.12)
        default: return Color.primary.opacity(0.06)
        }
    }
}
