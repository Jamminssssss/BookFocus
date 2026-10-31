import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        BookListView()
            .onOpenURL { url in
                handleDeepLink(url)
            }
    }
    
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "focusreader" else { return }
        
        if url.host == "stop" {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenEndPageInputFromDeepLink"),
                object: nil
            )
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Book.self, ReadingSession.self, PageMemo.self], inMemory: true)
}
