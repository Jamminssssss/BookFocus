//
//  ContentView.swift
//  BookFocus Watch Watch App
//
//  Created by JeaminPark on 1/11/26.
//

import SwiftUI

struct ContentView: View {
    @State private var books: [TimerStateManager.BookData] = []
    @State private var selectedBook: TimerStateManager.BookData?
    @State private var showTimerView = false
    @State private var refreshTimer: Timer?
    
    var body: some View {
        NavigationStack {
            if books.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Books")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Add books from the app")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List {
                    ForEach(books) { book in
                        Button {
                            selectedBook = book
                            showTimerView = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                Text("\(book.currentPage) / \(book.totalPages) pages")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Books")
            }
        }
        .sheet(isPresented: $showTimerView) {
            if let book = selectedBook {
                TimerView(book: book)
            }
        }
        .onAppear {
            _ = WatchSessionManager.shared   // 🔥 Activate WCSession (required)
            loadBooks()
            startRefreshTimer()
        }
        .onDisappear {
            refreshTimer?.invalidate()
        }
    }
    
    private func loadBooks() {
        books = TimerStateManager.shared.loadBooks()
    }
    
    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            loadBooks()
        }
    }
}

#Preview {
    ContentView()
}
