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
            .onOpenURL { url in
                handleDeepLink(url)
            }
    }
    
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "focusreader" else { return }
        
        if url.host == "stop" {
            // 위젯에서 스탑 버튼을 눌렀을 때
            // 약간의 딜레이를 주어 BookListView가 준비될 시간을 줌
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // BookListView로 알림 전송
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenEndPageInputFromDeepLink"),
                    object: nil
                )
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Book.self, ReadingSession.self, PageMemo.self], inMemory: true)
}
