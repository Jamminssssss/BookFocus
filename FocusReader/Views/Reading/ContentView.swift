import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        BookListView()
            .onAppear {
                // 🔥 동기화 모니터링 (콘솔 로그만)
                NotificationCenter.default.addObserver(
                    forName: Notification.Name("NSPersistentStoreRemoteChange"),
                    object: nil,
                    queue: .main
                ) { _ in
                    print("☁️ iCloud 동기화 발생")
                }
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Book.self, ReadingSession.self, PageMemo.self], inMemory: true)
}
