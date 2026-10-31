import Foundation

class TimerStateManager {
    static let shared = TimerStateManager()
    private let appGroupID = "group.com.Jaemin.FocusReader"
    private var userDefaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }
    
    private let statesMapKey = "timer.states.map"
    private let activeBookIDKey = "timer.activeBookID"
    private let booksDataKey = "books.data"
    
    private init() {}
    
    typealias TimerState = SharedTimerState
    
    // MARK: - Timer State Interactors
    
    func loadState(forBookID bookID: String) -> TimerState? {
        return loadAllStatesMap()[bookID]
    }
    
    func setActiveBookID(_ bookID: String, reloadWidget: Bool = true) {
        userDefaults?.set(bookID, forKey: activeBookIDKey)
    }
    
    func saveState(_ state: TimerState, reloadWidget: Bool = true) {
        let resolvedBookID = state.bookID ?? userDefaults?.string(forKey: activeBookIDKey) ?? UUID().uuidString
        guard let defaults = userDefaults else { return }
        
        var map = loadAllStatesMap()
        var updated = state
        updated.bookID = resolvedBookID
        map[resolvedBookID] = updated
        
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: statesMapKey)
            defaults.set(resolvedBookID, forKey: activeBookIDKey)
        }
        
        if reloadWidget {
            let widgetState = WidgetTimerState(
                bookID: resolvedBookID,
                bookTitle: state.bookTitle,
                bookAuthor: "",
                currentPage: state.currentPage,
                totalPages: state.totalPages,
                sessionStartDate: state.isRunning ? state.sessionStartTime : nil,
                accumulatedElapsed: state.pausedTime > 0 ? state.pausedTime : state.elapsedTime,
                format: state.format
            )
            widgetState.save()
        }
    }
    
    func saveStateAsync(_ state: TimerState, reloadWidget: Bool = true) async {
        saveState(state, reloadWidget: reloadWidget)
    }
    
    func loadActiveState() -> TimerState? {
        let map = loadAllStatesMap()
        let activeID = userDefaults?.string(forKey: activeBookIDKey)
        
        if let id = activeID, let state = map[id] {
            return state
        }
        
        if let firstState = map.values.first, let firstID = firstState.bookID {
            userDefaults?.set(firstID, forKey: activeBookIDKey)
            return firstState
        }
        return nil
    }
    
    func loadAllStatesMap() -> [String: TimerState] {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: statesMapKey),
              let map = try? JSONDecoder().decode([String: TimerState].self, from: data) else { return [:] }
        return map
    }
    
    func clearState() {
        guard let bookID = userDefaults?.string(forKey: activeBookIDKey),
              let defaults = userDefaults else { return }
        
        var map = loadAllStatesMap()
        map.removeValue(forKey: bookID)
        
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: statesMapKey)
        }
        defaults.removeObject(forKey: activeBookIDKey)
        WidgetTimerState.empty.save()
    }

    func removeState(forBookID bookID: String) {
        guard let defaults = userDefaults else { return }
        var map = loadAllStatesMap()
        map.removeValue(forKey: bookID)
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: statesMapKey)
        }
        if defaults.string(forKey: activeBookIDKey) == bookID {
            if let nextID = map.keys.first {
                defaults.set(nextID, forKey: activeBookIDKey)
            } else {
                defaults.removeObject(forKey: activeBookIDKey)
            }
        }
    }
    
    func clearActiveState() {
        guard let defaults = userDefaults else { return }
        defaults.removeObject(forKey: activeBookIDKey)
        defaults.removeObject(forKey: statesMapKey)
        WidgetTimerState.empty.save()
    }
    
    func getWidgetAction() -> String? {
        guard let defaults = userDefaults,
              let action = defaults.string(forKey: "widget.action") else { return nil }
        defaults.removeObject(forKey: "widget.action")
        return action
    }
    
    // MARK: - 📚 Watch Sync Data Models & Book Management
    
    typealias BookData = SharedBookData
    
    func loadBooks() -> [BookData] {
        guard let defaults = userDefaults,
              let data = defaults.data(forKey: booksDataKey),
              let books = try? JSONDecoder().decode([BookData].self, from: data) else {
            return []
        }
        return books
    }
    
    func saveBooks(_ books: [BookData]) {
        guard let defaults = userDefaults,
              let data = try? JSONEncoder().encode(books) else { return }
        defaults.set(data, forKey: booksDataKey)
    }
    
    func updateBook(_ book: BookData) {
        var books = loadBooks()
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            books[index] = book
        } else {
            books.append(book)
        }
        saveBooks(books)
    }
    
    // MARK: - Cover Image
    private var coverImagesDirectory: URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        let dir = containerURL.appendingPathComponent("CoverImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    func saveCoverImage(_ data: Data, forBookID bookID: String) {
        guard let fileURL = coverImagesDirectory?.appendingPathComponent(bookID) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    
    func loadCoverImage(forBookID bookID: String?) -> Data? {
        guard let bookID, let fileURL = coverImagesDirectory?.appendingPathComponent(bookID) else { return nil }
        return try? Data(contentsOf: fileURL)
    }
    
    func deleteCoverImage(forBookID bookID: String) {
        guard let fileURL = coverImagesDirectory?.appendingPathComponent(bookID) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
