//
//  BookListView.swift
//  FocusReader
//
//  Created by JeaminPark on 12/10/25.
//

import SwiftUI
import SwiftData

struct BookListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]
    
    @State private var showAddBook: Bool = false
    @State private var selectedBook: Book?
    
    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    ContentUnavailableView(
                        "No Books",
                        systemImage: "book.closed",
                        description: Text("Add a new book")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 30) {
                            ForEach(books) { book in
                                BookRowView(
                                    book: book,
                                    onDeleteTap: {
                                        deleteBook(book)
                                    }
                                )
                                .background(
                                    NavigationLink(destination: ReadingTimerView(book: book)) {
                                        EmptyView()
                                    }
                                    .opacity(0)
                                )
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddBook = true
                    } label: {
                        Label("Add Book", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddBook) {
                AddBookView()
            }
        }
    }
    
    private func deleteBook(_ book: Book) {
        withAnimation {
            // 이미지 파일도 삭제
            if let imagePath = book.imagePath,
               let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let imageURL = documentsDirectory.appendingPathComponent(imagePath)
                try? FileManager.default.removeItem(at: imageURL)
            }
            
            // 세션들도 함께 삭제
            if let sessions = book.sessions {
                for session in sessions {
                    modelContext.delete(session)
                }
            }
            
            // 메모들도 함께 삭제
            if let memos = book.memos {
                for memo in memos {
                    modelContext.delete(memo)
                }
            }
            
            modelContext.delete(book)
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to delete book: \(error)")
            }
        }
    }
}

struct BookRowView: View {
    let book: Book
    let onDeleteTap: () -> Void
    
    @State private var showingTimerView = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 20) {
                // 책 표지 이미지
                if let imagePath = book.imagePath,
                   let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let imageURL = documentsDirectory.appendingPathComponent(imagePath)
                    if let imageData = try? Data(contentsOf: imageURL),
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    } else {
                        placeholderImage
                    }
                } else {
                    placeholderImage
                }
                
                // 책 정보 (중앙에 표시)
                VStack(spacing: 12) {
                    Text(book.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    Text(book.author)
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "book.pages")
                            .foregroundColor(.blue)
                        Text("\(book.currentPage) / \(book.totalPages)")
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            
            // 메뉴 버튼 (오른쪽 상단)
            Menu {
                NavigationLink(destination: ReadingTimerView(book: book)) {
                    Label("Start Reading", systemImage: "play.fill")
                }
                
                NavigationLink(destination: MemoTimelineView(book: book)) {
                    Label("View Memos", systemImage: "note.text")
                }
                
                Button(role: .destructive, action: onDeleteTap) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color(.systemBackground).opacity(0.9))
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, 20)
    }
    
    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.2))
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .overlay {
                Image(systemName: "book.closed")
                    .font(.system(size: 60))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}
