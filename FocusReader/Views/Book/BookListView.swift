import SwiftUI
import SwiftData
import FamilyControls
import Combine
import UniformTypeIdentifiers // ⭐️ 추가: CSV 파일 선택을 위해 필요

// MARK: - Book List View
struct BookListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]

    @State private var showAddBook = false
    @State private var showLibrarySheet = false
    @StateObject private var timerManager = ReadingTimerManager.shared
    
    @StateObject private var storeManager = StoreKitManager.shared
    @State private var showPremiumSheet = false
    @State private var showThemeSheet = false
    @State private var showInsights = false
    
    @StateObject private var focusManager = FocusManager.shared
    @State private var showFocusSettings = false
    @State private var showAppPicker = false
    
    // 책장에서 선택된 책으로 이동하기 위한 타겟 ID 변수
    @State private var targetBookIDToScroll: PersistentIdentifier? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isIPad: Bool { horizontalSizeClass == .regular }

    @ObservedObject private var themeManager = ThemeManager.shared
    var paperColor: Color { themeManager.currentTheme.paperColor(isDark: colorScheme == .dark) }
    var inkColor: Color { themeManager.currentTheme.inkColor(isDark: colorScheme == .dark) }

    var body: some View {
        NavigationStack {
            ZStack {
                paperColor.ignoresSafeArea()

                VStack(spacing: 0) {
                    AnalogStatusBar()
                        .padding(.top, 12)
                        .opacity(timerManager.isRunning ? 0 : 1)
                        .animation(.easeInOut(duration: 0.3), value: timerManager.isRunning)

                    AdaptiveTopBannerView()
                        .opacity(timerManager.isRunning ? 0 : 1)
                        .frame(height: timerManager.isRunning ? 0 : nil)
                    
                    Group {
                        if books.isEmpty {
                            emptyStateView
                        } else {
                            // 책장 뷰와의 연동을 위한 ScrollViewReader 적용
                            ScrollViewReader { scrollProxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 16) {
                                        ForEach(books) { book in
                                            BookCoverFlowItemView(
                                                book: book, isIPad: isIPad, modelContext: modelContext,
                                                onDelete: { deleteBook(book) }
                                            )
                                            .id(book.persistentModelID) // 스크롤 타겟 식별자
                                            .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
                                            .scrollTransition(axis: .horizontal) { content, phase in
                                                content
                                                    .scaleEffect(phase.isIdentity ? 1.0 : 0.92)
                                                    .opacity(phase.isIdentity ? 1.0 : 0.6)
                                            }
                                        }
                                    }.scrollTargetLayout()
                                }
                                .contentMargins(.horizontal, isIPad ? 160 : 60, for: .scrollContent)
                                .scrollTargetBehavior(.viewAligned)
                                .onChange(of: targetBookIDToScroll) { _, newTargetID in
                                    // 책장에서 책을 탭하여 targetBookIDToScroll 변경 시 부드럽게 스크롤
                                    if let targetID = newTargetID {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                            scrollProxy.scrollTo(targetID, anchor: .center)
                                        }
                                        targetBookIDToScroll = nil
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    AdaptiveBottomBannerView()
                        .opacity(timerManager.isRunning ? 0 : 1)
                        .frame(height: timerManager.isRunning ? 0 : nil)
                        .animation(.easeInOut(duration: 0.3), value: timerManager.isRunning)
                    
                    bottomSketchTabBar
                        .opacity(timerManager.isRunning ? 0 : 1)
                        .disabled(timerManager.isRunning)
                        .animation(.easeInOut(duration: 0.3), value: timerManager.isRunning)
                }
            }
            .statusBarHidden(true)
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showAddBook) { AddBookView() }
            // 책장 시트에 책 선택 콜백 클로저 추가
            .fullScreenCover(isPresented: $showLibrarySheet) {
                LibraryShelfView { selectedBook in
                    targetBookIDToScroll = selectedBook.persistentModelID
                }
            }
            .fullScreenCover(isPresented: $showPremiumSheet) { PurchaseView() }
            .fullScreenCover(isPresented: $showThemeSheet) { ThemeSelectionView() }
            .fullScreenCover(isPresented: $showInsights) { ReadingInsightsView() }
            .fullScreenCover(isPresented: $timerManager.showEndPageInput) {
                if let bookID = timerManager.activeBookID,
                   let book = books.first(where: { $0.id == bookID }) {
                    EndPageInputView(book: book, session: timerManager.currentSession) {
                        timerManager.commitSession(to: book, context: modelContext)
                        syncAllBooksToWatch()
                    } onCancel: {
                        timerManager.cancelSession()
                    }
                }
            }
            .fullScreenCover(isPresented: $showFocusSettings) { focusSettingsSheet }
            .fullScreenCover(isPresented: $showAppPicker) {
                NavigationStack {
                    FamilyActivityPicker(selection: $focusManager.activitySelection)
                        .navigationTitle("Block These Apps").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAppPicker = false } } }
                }
            }
            .onAppear {
                WatchSyncManager.shared.modelContext = modelContext
                WatchSyncManager.shared.processPendingSessions()
                syncAllBooksToWatch()
                timerManager.processPendingWidgetAction()
                Task { await focusManager.checkAuthorization() }
            }
            // 책 수가 바뀌면 워치의 책 목록 갱신
            .onChange(of: books.count) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    syncAllBooksToWatch()
                }
            }
            .onChange(of: Set(books.map { $0.id })) { _, _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { syncAllBooksToWatch() } }
            .onChange(of: Set(books.map { "\($0.id)-\($0.currentPage)" })) { _, _ in syncAllBooksToWatch() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    WatchSyncManager.shared.modelContext = modelContext
                    WatchSyncManager.shared.processPendingSessions()
                    syncAllBooksToWatch()
                    timerManager.processPendingWidgetAction()
                    Task { await focusManager.checkAuthorization() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenEndPageInputFromDeepLink"))) { _ in
                if timerManager.currentSession != nil { timerManager.stopTimer() }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TimerCompletedFromNotification"))) { _ in
                if timerManager.currentSession != nil { timerManager.stopTimer() }
            }
        }
    }
    
    // MARK: - 하단 탭 바
    private var bottomSketchTabBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Button { handleFocusTap() } label: {
                VStack(spacing: 8) {
                    Image(systemName: focusManager.focusModeEnabled ? "shield" : "shield.slash")
                        .font(.title3)
                    Text(focusManager.focusModeEnabled ? "on" : "off")
                        .font(.custom("ChalkboardSE-Regular", size: 12))
                }
                .foregroundStyle(inkColor)
                .frame(maxWidth: .infinity)
            }
            
            Button { showLibrarySheet = true } label: {
                VStack(spacing: 8) {
                    Image(systemName: "books.vertical")
                        .font(.title3)
                    Text("shelf")
                        .font(.custom("ChalkboardSE-Regular", size: 12))
                }
                .foregroundStyle(inkColor)
                .frame(maxWidth: .infinity)
            }
            
            Button { handleAddBookTap() } label: {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.up")
                        .font(.title3)
                        .frame(width: 38, height: 54)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(inkColor, lineWidth: 1.5)
                                .rotationEffect(.degrees(-3))
                        )
                }
                .foregroundStyle(inkColor)
                .frame(maxWidth: .infinity)
            }

            Button { showInsights = true } label: {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title3)
                    Text("insights")
                        .font(.custom("ChalkboardSE-Regular", size: 12))
                }
                .foregroundStyle(inkColor)
                .frame(maxWidth: .infinity)
            }
            
            Button { showThemeSheet = true } label: {
                VStack(spacing: 8) {
                    Image(systemName: "paintpalette")
                        .font(.title3)
                    Text("theme")
                        .font(.custom("ChalkboardSE-Regular", size: 12))
                }
                .foregroundStyle(inkColor)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack {
            Spacer()
            Text("first thought when wake =\nseed for whole day. books\nplant one small good thought,\ngrow good day tree.")
                .font(.custom("ChalkboardSE-Regular", size: 18))
                .foregroundStyle(inkColor)
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 32)
            Spacer()
            
            HStack(spacing: 0) {
                Spacer().frame(maxWidth: .infinity)
                Spacer().frame(maxWidth: .infinity)
                
                VStack(alignment: .center, spacing: 4) {
                    Text("you\nadd\nbook")
                        .font(.custom("ChalkboardSE-Regular", size: 14))
                        .foregroundStyle(inkColor)
                        .multilineTextAlignment(.center)
                        .rotationEffect(.degrees(-6))
                    
                    SketchLoopyArrow()
                        .stroke(
                            inkColor,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 44, height: 64)
                }
                .frame(maxWidth: .infinity)
                
                Spacer().frame(maxWidth: .infinity)
                Spacer().frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }
    
    private var focusSettingsSheet: some View {
        NavigationStack {
            Form {
                if focusManager.isFocusModeActive { Section { HStack(spacing: 10) { Image(systemName: "shield").foregroundStyle(.black); Text("Focus Mode is Active").font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(.black) } } }
                if !focusManager.isAuthorized { Section { Button { Task { await focusManager.requestAuthorization() } } label: { Label("Allow Screen Time Access", systemImage: "lock.shield") } } footer: { Text("Screen Time permission is required to block apps while reading.") } }
                Section {
                    Toggle(isOn: $focusManager.focusModeEnabled) { Label("Block Apps While Reading", systemImage: "shield.lefthalf.filled") }.disabled(!focusManager.isAuthorized)
                    if focusManager.focusModeEnabled && focusManager.isAuthorized { Button { showFocusSettings = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showAppPicker = true } } label: { HStack { Label("Choose Apps to Block", systemImage: "square.grid.2x2"); Spacer(); let count = focusManager.activitySelection.applicationTokens.count; if count > 0 { Text("\(count) selected").foregroundStyle(.secondary).font(.subheadline) }; Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) } }.foregroundStyle(.primary) }
                } header: { Text("Focus Mode") } footer: { if focusManager.isAuthorized { Text("Selected apps are blocked while the reading timer is running.") } }
            }.navigationTitle("Focus Settings").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showFocusSettings = false }.foregroundStyle(.black) } }
        }
    }
    
    private func handleFocusTap() { if storeManager.isPremium { showFocusSettings = true } else { showPremiumSheet = true } }
    
    private func handleAddBookTap() {
        if FreeLimitManager.shared.canAddBook(isPremium: storeManager.isPremium, currentBookCount: books.count) {
            showAddBook = true
        } else {
            showPremiumSheet = true
        }
    }

    private func deleteBook(_ book: Book) {
        let bookID = book.id.uuidString
        let dueDate = book.dueDate
        if timerManager.activeBookID == book.id {
            timerManager.cancelSession()
        }
        withAnimation {
            book.sessions?.forEach { modelContext.delete($0) }
            book.memos?.forEach { modelContext.delete($0) }
            modelContext.delete(book)
            try? modelContext.save()
        }
        LoanCalendarManager.shared.removeLoanEvents(forBookID: bookID)
        TimerStateManager.shared.deleteCoverImage(forBookID: bookID)
        if let dueDate {
            refreshDueReminderGroup(for: dueDate, excludingBookID: bookID)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { syncAllBooksToWatch() }
    }
    
    private func syncAllBooksToWatch() {
        for book in books {
            if let coverData = book.coverImageData {
                TimerStateManager.shared.saveCoverImage(coverData, forBookID: book.id.uuidString)
            }
        }
        let bookDataList = books.map { TimerStateManager.BookData.from($0) }
        WatchSyncManager.shared.sendBooksToWatch(bookDataList, isFullSnapshot: true)
    }

    private func refreshDueReminderGroup(for dueDate: Date, excludingBookID: String? = nil) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: dueDate)
        let currentBooks = (try? modelContext.fetch(FetchDescriptor<Book>())) ?? books
        let remainingTitles = currentBooks
            .filter {
                $0.id.uuidString != excludingBookID
                    && $0.loanStatus != .returned
                    && $0.dueDate.map { Calendar.current.isDate($0, inSameDayAs: dueDate) } == true
            }
            .map(\.title)

        WatchDueReminderScheduler.cancelGroup(dateKey: dateKey)
        WatchSyncManager.shared.cancelDueReminderGroupOnWatch(dateKey: dateKey)
        guard !remainingTitles.isEmpty else { return }
        let payload = WatchDueReminderScheduler.DueGroupPayload(
            dateKey: dateKey,
            dueDate: dueDate,
            bookTitles: remainingTitles
        )
        Task {
            await WatchDueReminderScheduler.scheduleGroup(payload)
            WatchSyncManager.shared.sendDueReminderGroupToWatch(payload)
        }
    }
}

// MARK: - Sketch Loopy Arrow
struct SketchLoopyArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: w * 0.3, y: 0))
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.5),
            control1: CGPoint(x: w * 0.9, y: h * 0.05),
            control2: CGPoint(x: w * 1.0, y: h * 0.45)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.45, y: h * 0.6),
            control1: CGPoint(x: w * 0.1, y: h * 0.55),
            control2: CGPoint(x: w * 0.1, y: h * 0.65)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.55, y: h * 0.95),
            control: CGPoint(x: w * 0.7, y: h * 0.75)
        )
        path.move(to: CGPoint(x: w * 0.4, y: h * 0.85))
        path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.95))
        path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.83))
        
        return path
    }
}

// MARK: - Library Shelf View
struct LibraryShelfView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isIPad: Bool { horizontalSizeClass == .regular }
    
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]
    @ObservedObject private var themeManager = ThemeManager.shared
    
    var onSelectBook: ((Book) -> Void)? = nil
    
    // ⭐️ 추가: Goodreads 가져오기를 위한 프로퍼티
    @Environment(\.modelContext) private var modelContext
    @StateObject private var storeManager = StoreKitManager.shared
    @StateObject private var importManager = GoodreadsImportManager()
    @State private var showFileImporter = false
    @State private var showImportProgress = false
    @State private var showPremiumSheet = false
    
    var paperColor: Color { themeManager.currentTheme.paperColor(isDark: colorScheme == .dark) }
    var inkColor: Color { themeManager.currentTheme.inkColor(isDark: colorScheme == .dark) }
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: isIPad ? 160 : 105, maximum: isIPad ? 200 : 135), spacing: isIPad ? 28 : 20)]
    }

    var body: some View {
        ZStack {
            paperColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 🛠️ 수정된 상단 네비게이션 바 영역
                HStack {
                    // ⭐️ "my library" 텍스트를 제거하고 CSV 가져오기 버튼을 왼쪽(leading)으로 이동
                    Button {
                        if storeManager.isPremium {
                            showFileImporter = true
                        } else {
                            showPremiumSheet = true
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title2)
                            .foregroundStyle(inkColor)
                    }
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(inkColor)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                if books.isEmpty {
                    Spacer()
                    Text("no books on your shelf yet.")
                        .font(.custom("ChalkboardSE-Regular", size: 16))
                        .foregroundStyle(inkColor.opacity(0.6))
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: columns, spacing: isIPad ? 36 : 28) {
                            ForEach(books) { book in
                                LibraryBookGridItem(book: book, inkColor: inkColor, isIPad: isIPad)
                                    .onTapGesture {
                                        onSelectBook?(book)
                                        dismiss()
                                    }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        // ⭐️ 추가: 파일 선택기 및 가져오기 시트 연결
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let selectedURL = urls.first else { return }
                showImportProgress = true
                Task {
                    await importManager.importFromCSV(url: selectedURL, context: modelContext, existingBooks: books)
                }
            case .failure(let error):
                print("CSV 가져오기 실패: \(error)")
            }
        }
        .sheet(isPresented: $showImportProgress) {
            GoodreadsImportProgressView(manager: importManager)
        }
        .fullScreenCover(isPresented: $showPremiumSheet) {
            PurchaseView() // 프리미엄 결제 화면 호출
        }
    }
}

// MARK: - Library Book Grid Item
struct LibraryBookGridItem: View {
    let book: Book
    let inkColor: Color
    let isIPad: Bool
    
    @State private var coverImage: UIImage? = nil
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let coverImage = coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.clear
                        .overlay {
                            Image(systemName: "book")
                                .font(.system(size: isIPad ? 40 : 28, weight: .ultraLight))
                                .foregroundStyle(inkColor.opacity(0.3))
                        }
                }
            }
            .frame(width: isIPad ? 150 : 105, height: isIPad ? 225 : 155)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(inkColor, lineWidth: 1.5))
            .shadow(color: inkColor == .black ? .black.opacity(0.08) : .white.opacity(0.08), radius: 0, x: 3, y: 3)
            
            VStack(spacing: 2) {
                Text(book.title)
                    .font(.custom("ChalkboardSE-Bold", size: isIPad ? 15 : 13))
                    .foregroundStyle(inkColor)
                    .lineLimit(1)
                
                Text(book.isEbook ? "\((Double(book.currentPage) / 100).formatted(.percent.precision(.fractionLength(0))))" : "\(book.currentPage)/\(book.totalPages)")
                    .font(.custom("ChalkboardSE-Regular", size: isIPad ? 13 : 11))
                    .foregroundStyle(inkColor.opacity(0.6))
            }
            .frame(maxWidth: isIPad ? 150 : 105)
        }
        .contentShape(Rectangle())
        .task(id: book.coverImageData) {
            if let data = book.coverImageData {
                Task.detached(priority: .userInitiated) {
                    let image = UIImage(data: data)
                    await MainActor.run { coverImage = image }
                }
            } else {
                coverImage = nil
            }
        }
    }
}

// MARK: - Analog Status Bar
struct AnalogStatusBar: View {
    @State private var timeString: String = ""
    @State private var batteryLevel: Int = 100
    @State private var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    
    @Environment(\.colorScheme) private var colorScheme
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    @ObservedObject private var themeManager = ThemeManager.shared
    var inkColor: Color { themeManager.currentTheme.inkColor(isDark: colorScheme == .dark) }
    var paperColor: Color { themeManager.currentTheme.paperColor(isDark: colorScheme == .dark) }
    
    private var batteryColor: Color {
        if isLowPowerMode {
            return .yellow
        } else if batteryLevel <= 20 {
            return .red
        } else {
            return .green
        }
    }
    
    var body: some View {
        HStack(alignment: .center) {
            Text(timeString)
                .font(.custom("ChalkboardSE-Regular", size: 14))
                .foregroundStyle(inkColor)
                .padding(.leading, 32)
                .onReceive(timer) { _ in updateTime() }
            
            Spacer()
            
            HStack(spacing: 1.5) {
                ZStack(alignment: .center) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(inkColor.opacity(0.1))
                            .frame(width: 36, height: 16)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(batteryColor)
                            .frame(width: max(0, CGFloat(36) * (CGFloat(batteryLevel) / 100.0)), height: 16)
                    }
                    
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(inkColor, lineWidth: 1.2)
                        .frame(width: 36, height: 16)
                    
                    Text("\((Double(batteryLevel) / 100).formatted(.percent.precision(.fractionLength(0))))")
                        .font(.custom("ChalkboardSE-Bold", size: 9))
                        .foregroundStyle(inkColor)
                }
                
                RoundedRectangle(cornerRadius: 1)
                    .fill(inkColor)
                    .frame(width: 2, height: 6)
            }
            .padding(.trailing, 32)
        }
        .onAppear {
            updateTime()
            UIDevice.current.isBatteryMonitoringEnabled = true
            updateBatteryLevel()
            updatePowerState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            updateBatteryLevel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            updatePowerState()
        }
    }
    
    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        timeString = formatter.string(from: Date())
    }
    
    private func updateBatteryLevel() {
        let level = UIDevice.current.batteryLevel
        if level >= 0 {
            batteryLevel = Int(level * 100)
        }
    }
    
    private func updatePowerState() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

// MARK: - Book Cover Flow Item View
struct BookCoverFlowItemView: View {
    let book: Book
    let isIPad: Bool
    let modelContext: ModelContext
    let onDelete: () -> Void
    
    @ObservedObject private var timerManager = ReadingTimerManager.shared
    @State private var isFlipped = false
    @State private var showMemoSheet = false
    @State private var showRereadSheet = false
    @State private var showTimerPickerSheet = false
    @State private var showPageProgressSheet = false
    
    @State private var cachedCoverImage: UIImage? = nil
    
    @State private var selectedHours: Int = 0
    @State private var selectedMinutes: Int = 15
    @State private var selectedSeconds: Int = 0
    
    @AppStorage("savedFavoriteTimersSec") private var favoriteTimersString: String = "30,300,900,1800,3600"
    
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeManager = ThemeManager.shared
    var paperColor: Color { themeManager.currentTheme.paperColor(isDark: colorScheme == .dark) }
    var inkColor: Color { themeManager.currentTheme.inkColor(isDark: colorScheme == .dark) }
    
    private var isThisBookActive: Bool { timerManager.activeBookID == book.id }
    private var hasMemos: Bool { guard let memos = book.memos else { return false }; return !memos.isEmpty }
    private var isCompleted: Bool { book.currentPage >= book.totalPages }
    private var coverSize: CGSize { isIPad ? CGSize(width: 350, height: 525) : CGSize(width: 250, height: 375) }
    
    private var currentTotalSeconds: Int {
        selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds
    }
    
    private var favoriteTimersList: [Int] {
        favoriteTimersString.split(separator: ",").compactMap { Int($0) }
    }
    
    var body: some View {
        ZStack {
            frontCardView.opacity(isFlipped ? 0 : 1).allowsHitTesting(!isFlipped)
            backCardView.scaleEffect(x: -1, y: 1).opacity(isFlipped ? 1 : 0).allowsHitTesting(isFlipped)
        }
        .frame(width: coverSize.width, height: coverSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(inkColor, lineWidth: 2))
        .compositingGroup()
        .shadow(color: inkColor == .black ? .black.opacity(0.1) : .white.opacity(0.1), radius: 0, x: 4, y: 4)
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isFlipped)
        .contextMenu {
            Button { showPageProgressSheet = true } label: {
                Label(LocalizedStringKey(book.isEbook ? "log progress." : "log page."), systemImage: "bookmark")
            }
            Button(role: .destructive) { onDelete() } label: { Label("Delete Book", systemImage: "trash") }
        }
        .fullScreenCover(isPresented: $showMemoSheet) { MemoTimelineView(book: book) }
        .fullScreenCover(isPresented: $showRereadSheet) { RereadStartPageSheet(book: book, isPresented: $showRereadSheet) }
        .sheet(isPresented: $showTimerPickerSheet) {
            timerSelectionSheet
        }
        .sheet(isPresented: $showPageProgressSheet) {
            PageProgressInputView(book: book)
        }
        .onChange(of: showRereadSheet) { _, newValue in
            if !newValue { isFlipped = false }
        }
        .task(id: book.coverImageData) {
            if let data = book.coverImageData {
                Task.detached(priority: .userInitiated) {
                    let image = UIImage(data: data)
                    await MainActor.run { cachedCoverImage = image }
                }
            } else {
                cachedCoverImage = nil
            }
        }
    }
    
    private var frontCardView: some View {
        coverImageView
            .overlay(alignment: .topTrailing) {
                if isCompleted { Image(systemName: "checkmark.seal").font(.title).foregroundStyle(inkColor).padding(12) }
            }
            .overlay(alignment: .topLeading) {
                if book.loanStatus == .returned {
                    loanBadgeView(text: "RETURNED", icon: "checkmark.circle.fill")
                } else if book.loanStatus == .renewed {
                    loanBadgeView(text: "RENEWED", icon: "arrow.triangle.2.circlepath")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isFlipped.toggle()
            }
    }
    
    private func loanBadgeView(text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
                .font(.custom("ChalkboardSE-Bold", size: 11))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(paperColor)
        .foregroundStyle(inkColor)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(inkColor, lineWidth: 1.5))
        .padding(12)
    }
    
    private var backCardView: some View {
        ZStack {
            paperColor
            VStack(spacing: 0) {
                HStack {
                    if hasMemos { Button { showMemoSheet = true } label: { Image(systemName: "pencil").font(.title2).foregroundStyle(inkColor) } } else { Image(systemName: "pencil").font(.title2).opacity(0) }
                    Spacer()
                    Button {
                        isFlipped = false
                    } label: { Image(systemName: "xmark").font(.title2).foregroundStyle(inkColor) }
                }.padding([.horizontal, .top], 16)
                
                Spacer(minLength: 6)
                VStack(spacing: 6) {
                    Text(book.title).font(.custom("ChalkboardSE-Bold", size: isIPad ? 26 : 22)).minimumScaleFactor(0.6).lineLimit(3).multilineTextAlignment(.center).foregroundStyle(inkColor)
                    Text(book.author).font(.custom("ChalkboardSE-Regular", size: 16)).minimumScaleFactor(0.8).foregroundStyle(inkColor.opacity(0.7)).lineLimit(1)
                }.padding(.horizontal, 16)
                
                Spacer(minLength: 6)
                
                HStack(spacing: 8) {
                    Button {
                        withAnimation {
                            setLoanStatus(book.loanStatus == .returned ? .borrowed : .returned)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: book.loanStatus == .returned ? "checkmark.square.fill" : "square")
                            Text("Returned").font(.custom("ChalkboardSE-Bold", size: 12))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(book.loanStatus == .returned ? inkColor.opacity(0.12) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(inkColor, lineWidth: 1.2))
                        .foregroundStyle(inkColor)
                    }
                    
                    Button {
                        withAnimation {
                            setLoanStatus(book.loanStatus == .renewed ? .borrowed : .renewed)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: book.loanStatus == .renewed ? "checkmark.square.fill" : "square")
                            Text("Renewed").font(.custom("ChalkboardSE-Bold", size: 12))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(book.loanStatus == .renewed ? inkColor.opacity(0.12) : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(inkColor, lineWidth: 1.2))
                        .foregroundStyle(inkColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                
                HStack(spacing: 0) {
                    Button { showPageProgressSheet = true } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 3) {
                                Text(book.isEbook ? "progress" : "page")
                                Image(systemName: "square.and.pencil").font(.system(size: 11))
                            }
                            .font(.custom("ChalkboardSE-Regular", size: 12))
                            .foregroundStyle(inkColor.opacity(0.6))

                            if book.isEbook {
                                Text("\((Double(book.currentPage) / 100).formatted(.percent.precision(.fractionLength(0))))")
                                    .font(.custom("ChalkboardSE-Bold", size: 16))
                                    .foregroundStyle(inkColor)
                            } else {
                                Text("\(book.currentPage) / \(book.totalPages)")
                                    .font(.custom("ChalkboardSE-Bold", size: 16))
                                    .foregroundStyle(inkColor)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(LocalizedStringKey(book.isEbook ? "log progress." : "log page.")))
                    .accessibilityValue(book.isEbook ? "\(book.currentPage)%" : "\(book.currentPage) / \(book.totalPages)")
                    .accessibilityHint("Save where you left off without a timer.")
                    
                    Rectangle().fill(inkColor).frame(width: 1, height: 32)
                    
                    Button {
                        if isThisBookActive && timerManager.isRunning { return }
                        timerManager.requestNotificationPermission()
                        showTimerPickerSheet = true
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 3) {
                                Text("time")
                                Image(systemName: "timer").font(.system(size: 11))
                            }
                            .font(.custom("ChalkboardSE-Regular", size: 12)).foregroundStyle(inkColor.opacity(0.6))
                            
                            Text(totalReadingTime).font(.custom("ChalkboardSE-Bold", size: 16)).foregroundStyle(inkColor)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }.padding(.vertical, 12).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5)).padding(.horizontal, 16)
                
                Spacer(minLength: 6)
                VStack(spacing: 14) {
                    if isCompleted {
                        Button { showRereadSheet = true } label: { HStack { Image(systemName: "arrow.counterclockwise"); Text("Reread") }.font(.custom("ChalkboardSE-Bold", size: 16)).foregroundStyle(inkColor).frame(maxWidth: .infinity).padding(.vertical, 14).overlay(RoundedRectangle(cornerRadius: 25).stroke(inkColor, lineWidth: 1.5)) }
                    } else {
                        if isThisBookActive && (timerManager.isRunning || timerManager.elapsedTime > 0) {
                            Text(timerManager.formattedTime).font(.custom("ChalkboardSE-Bold", size: 36)).lineLimit(1).minimumScaleFactor(0.5).allowsTightening(true).fixedSize(horizontal: true, vertical: true).foregroundStyle(inkColor).transition(.scale.combined(with: .opacity))
                        }
                        HStack(spacing: 12) {
                            Button {
                                if !isThisBookActive || timerManager.elapsedTime == 0 {
                                    timerManager.isTimerMode = false
                                    timerManager.targetSeconds = 0
                                    timerManager.cancelPendingNotification()
                                }
                                TimerStateManager.shared.setActiveBookID(book.id.uuidString)
                                timerManager.toggleTimer(for: book)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: isThisBookActive && timerManager.isRunning ? "pause" : "play")
                                    Text(isThisBookActive && timerManager.isRunning ? "Pause" : (isThisBookActive && timerManager.elapsedTime > 0 ? "Resume" : "Start Reading")).font(.custom("ChalkboardSE-Regular", size: 16))
                                }.frame(maxWidth: .infinity).padding(.vertical, 14).background(isThisBookActive && timerManager.isRunning ? inkColor.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 25)).overlay(RoundedRectangle(cornerRadius: 25).stroke(inkColor, lineWidth: 1.5)).foregroundStyle(inkColor)
                            }
                            if isThisBookActive && (timerManager.isRunning || timerManager.elapsedTime > 0) {
                                Button {
                                    timerManager.cancelPendingNotification()
                                    timerManager.stopTimer()
                                } label: {
                                    HStack(spacing: 6) { Image(systemName: "stop"); Text("Stop").font(.custom("ChalkboardSE-Regular", size: 16)) }.frame(maxWidth: .infinity).padding(.vertical, 14).overlay(RoundedRectangle(cornerRadius: 25).stroke(inkColor, lineWidth: 1.5)).foregroundStyle(inkColor)
                                }.transition(.move(edge: .trailing).combined(with: .opacity))
                            }
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16).animation(.spring(response: 0.35, dampingFraction: 0.8), value: isThisBookActive).animation(.spring(response: 0.35, dampingFraction: 0.8), value: timerManager.isRunning)
            }
        }
    }
    
    private var timerSelectionSheet: some View {
        ZStack {
            paperColor.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Set Reading Goal")
                    .font(.custom("ChalkboardSE-Bold", size: 20))
                    .foregroundStyle(inkColor)
                    .padding(.top, 18)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("favorites")
                            .font(.custom("ChalkboardSE-Regular", size: 13))
                            .foregroundStyle(inkColor.opacity(0.6))
                        Spacer()
                        
                        Button {
                            addFavorite(currentTotalSeconds)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("save current")
                            }
                            .font(.custom("ChalkboardSE-Bold", size: 12))
                            .foregroundStyle(currentTotalSeconds > 0 ? inkColor : inkColor.opacity(0.3))
                        }
                        .disabled(currentTotalSeconds == 0)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(favoriteTimersList, id: \.self) { sec in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        selectedHours = sec / 3600
                                        selectedMinutes = (sec % 3600) / 60
                                        selectedSeconds = sec % 60
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(formatPresetLabel(sec))
                                            .font(.custom("ChalkboardSE-Bold", size: 13))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(currentTotalSeconds == sec ? inkColor.opacity(0.12) : Color.clear)
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(inkColor, lineWidth: 1.2))
                                    .foregroundStyle(inkColor)
                                }
                                .contextMenu {
                                    Button(role: .destructive) { removeFavorite(sec) } label: {
                                        Label("Delete Favorite", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, 22)
                
                HStack(spacing: 0) {
                    Picker("Hours", selection: $selectedHours) {
                        ForEach(0...5, id: \.self) { h in
                            Text("\(h)h").font(.custom("ChalkboardSE-Bold", size: 15)).tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                    
                    Picker("Minutes", selection: $selectedMinutes) {
                        ForEach(0...59, id: \.self) { m in
                            Text("\(m)m").font(.custom("ChalkboardSE-Bold", size: 15)).tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("Seconds", selection: $selectedSeconds) {
                        ForEach(0...59, id: \.self) { s in
                            Text("\(s)s").font(.custom("ChalkboardSE-Bold", size: 15)).tag(s)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 115)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(inkColor.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                
                Button {
                    let totalSec = max(1, currentTotalSeconds)
                    timerManager.isTimerMode = true
                    timerManager.targetSeconds = totalSec
                    
                    TimerStateManager.shared.setActiveBookID(book.id.uuidString)
                    timerManager.toggleTimer(for: book)
                    
                    showTimerPickerSheet = false
                } label: {
                    Text(currentTotalSeconds > 0 ? "Start \(formatPresetLabel(currentTotalSeconds)) Timer" : "Start 1s Timer")
                        .font(.custom("ChalkboardSE-Bold", size: 15))
                        .foregroundStyle(inkColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(inkColor.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 25).stroke(inkColor, lineWidth: 1.5))
                }
                .padding(.horizontal, 22)
                
                Button {
                    timerManager.isTimerMode = false
                    timerManager.targetSeconds = 0
                    timerManager.cancelPendingNotification()
                    
                    TimerStateManager.shared.setActiveBookID(book.id.uuidString)
                    timerManager.toggleTimer(for: book)
                    showTimerPickerSheet = false
                } label: {
                    Text("start stopwatch (open-ended)")
                        .font(.custom("ChalkboardSE-Regular", size: 13))
                        .foregroundStyle(inkColor.opacity(0.6))
                        .underline()
                }
                
                Spacer()
            }
        }
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
    }
    
    private func addFavorite(_ seconds: Int) {
        guard seconds > 0 else { return }
        var list = favoriteTimersList
        if !list.contains(seconds) {
            list.append(seconds)
            list.sort()
            favoriteTimersString = list.map { String($0) }.joined(separator: ",")
        }
    }
    
    private func removeFavorite(_ seconds: Int) {
        var list = favoriteTimersList
        list.removeAll { $0 == seconds }
        favoriteTimersString = list.map { String($0) }.joined(separator: ",")
    }
    
    private func formatPresetLabel(_ totalSec: Int) -> String {
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        
        var parts: [String] = []
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if s > 0 { parts.append("\(s)s") }
        
        return parts.isEmpty ? "0s" : parts.joined(separator: " ")
    }

    private func setLoanStatus(_ status: LoanStatus) {
        book.loanStatus = status
        book.lastUpdated = Date()
        try? modelContext.save()
        WatchSyncManager.shared.sendBooksToWatch([TimerStateManager.BookData.from(book)])

        if status == .returned {
            LoanCalendarManager.shared.removeLoanEvents(forBookID: book.id.uuidString)
        } else {
            LoanCalendarManager.shared.updateLoanEvents(
                bookID: book.id.uuidString,
                title: book.title,
                author: book.author,
                checkoutDate: book.checkoutDate,
                dueDate: book.dueDate
            )
        }

        guard let dueDate = book.dueDate else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: dueDate)
        WatchDueReminderScheduler.cancelGroup(dateKey: dateKey)
        WatchSyncManager.shared.cancelDueReminderGroupOnWatch(dateKey: dateKey)

        let allBooks = (try? modelContext.fetch(FetchDescriptor<Book>())) ?? []
        let titles = allBooks.filter {
            $0.loanStatus != .returned
                && $0.dueDate.map { Calendar.current.isDate($0, inSameDayAs: dueDate) } == true
        }.map(\.title)
        guard !titles.isEmpty else { return }
        let payload = WatchDueReminderScheduler.DueGroupPayload(
            dateKey: dateKey,
            dueDate: dueDate,
            bookTitles: titles
        )
        Task {
            await WatchDueReminderScheduler.scheduleGroup(payload)
            WatchSyncManager.shared.sendDueReminderGroupToWatch(payload)
        }
    }
    
    private var coverImageView: some View {
        Group {
            if let uiImage = cachedCoverImage {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                paperColor.overlay {
                    Image(systemName: "book").font(.system(size: isIPad ? 80 : 50, weight: .ultraLight)).foregroundStyle(inkColor.opacity(0.3))
                }
            }
        }.frame(width: coverSize.width, height: coverSize.height)
    }
    
    private var totalReadingTime: String { guard let sessions = book.sessions else { return "0m" }; let totalSeconds = sessions.reduce(0) { $0 + $1.duration }; return formatTime(minutes: Int(totalSeconds / 60)) }
    private func formatTime(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return mins > 0
                ? String(localized: "\(hours)h \(mins)m")
                : String(localized: "\(hours)h")
        }
        return String(localized: "\(mins)m")
    }
}

struct RereadStartPageSheet: View {
    let book: Book; @Binding var isPresented: Bool; @Environment(\.modelContext) private var modelContext; @Environment(\.horizontalSizeClass) private var horizontalSizeClass; @State private var startPage: Int = 1; private var isIPad: Bool { horizontalSizeClass == .regular }
    
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeManager = ThemeManager.shared
    var paperColor: Color { themeManager.currentTheme.paperColor(isDark: colorScheme == .dark) }
    var inkColor: Color { themeManager.currentTheme.inkColor(isDark: colorScheme == .dark) }
    
    var body: some View {
        NavigationStack {
            ZStack {
                paperColor.ignoresSafeArea()
                VStack(spacing: 30) {
                    Spacer(); Image(systemName: "arrow.counterclockwise").font(.system(size: isIPad ? 80 : 60, weight: .light)).foregroundStyle(inkColor)
                    VStack(spacing: 12) { Text("reread_title").font(.custom("ChalkboardSE-Bold", size: isIPad ? 32 : 24)).foregroundStyle(inkColor); Text("reread_subtitle").font(.custom("ChalkboardSE-Regular", size: isIPad ? 20 : 16)).foregroundColor(inkColor.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal) }
                    
                    VStack(spacing: 16) {
                        HStack {
                            Text(book.isEbook ? "start progress" : "start_page_label").font(.custom("ChalkboardSE-Regular", size: 18)).foregroundStyle(inkColor)
                            Spacer()
                            Text(book.isEbook ? "\((Double(startPage) / 100).formatted(.percent.precision(.fractionLength(0))))" : "\(startPage)").font(.custom("ChalkboardSE-Bold", size: 22)).foregroundColor(inkColor)
                        }.padding(.horizontal, 24)
                        
                        Picker("start_page_picker", selection: $startPage) {
                            let range = book.isEbook ? 0...100 : 1...book.totalPages
                            ForEach(range, id: \.self) { val in
                                Text(book.isEbook ? "\((Double(val) / 100).formatted(.percent.precision(.fractionLength(0))))" : "\(val)").tag(val)
                            }
                        }.pickerStyle(.wheel).frame(height: 150)
                    }.padding(.vertical, 20).overlay(RoundedRectangle(cornerRadius: 16).stroke(inkColor, lineWidth: 1.5)).padding(.horizontal, 20)
                    
                    Spacer(); Button { startReading() } label: { HStack { Image(systemName: "checkmark"); Text("start_reading") }.font(.custom("ChalkboardSE-Bold", size: 18)).foregroundColor(inkColor).frame(maxWidth: .infinity).padding(.vertical, 16).overlay(RoundedRectangle(cornerRadius: 25).stroke(inkColor, lineWidth: 1.5)) }.padding(.horizontal, 20).padding(.bottom, 20)
                }
            }.navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("cancel") { isPresented = false }.font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor) } }
        }
    }
    
    private func startReading() {
        book.currentPage = startPage; book.isCompleted = false; book.lastUpdated = Date();
        if book.loanStatus == .returned {
            book.loanStatus = .renewed
        }
        try? modelContext.save();
        let bookData = TimerStateManager.BookData.from(book)
        WatchSyncManager.shared.sendBooksToWatch([bookData]); isPresented = false
    }
}
