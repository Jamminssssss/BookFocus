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
    @State private var currentIndex: Int = 0
    @State private var showDetails: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 배경 그라데이션
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
                        // 캐러셀
                        TabView(selection: $currentIndex) {
                            ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                                BookCardView(
                                    book: book,
                                    onDelete: { deleteBook(book) },
                                    showDetails: $showDetails
                                )
                                .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: books.count > 1 ? .automatic : .never))
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                        .onChange(of: currentIndex) { oldValue, newValue in
                            // 페이지가 변경되면 상세보기 숨김
                            showDetails = false
                        }
                        
                        // 하단 정보 영역
                        if !books.isEmpty {
                            bottomInfoView
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddBook = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .sheet(isPresented: $showAddBook) {
                AddBookView()
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 80))
                .foregroundStyle(.blue.opacity(0.5))
            
            Text("No Books Yet")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Start your reading journey by adding a book")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
    
    // MARK: - Bottom Info
    private var bottomInfoView: some View {
        VStack(spacing: 16) {
            // 페이지 인디케이터
            if books.count > 1 {
                Text("\(currentIndex + 1) / \(books.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            
            // 빠른 액션 버튼 (상세보기 상태일 때만 표시)
            if showDetails {
                Spacer()
                    .frame(height: 20)
            }
        }
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: -5)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showDetails)
    }
    
    private func deleteBook(_ book: Book) {
        withAnimation {
            // 이미지 파일 삭제
            if let imagePath = book.imagePath,
               let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let imageURL = documentsDirectory.appendingPathComponent(imagePath)
                try? FileManager.default.removeItem(at: imageURL)
            }
            
            // 관련 데이터 삭제
            if let sessions = book.sessions {
                for session in sessions {
                    modelContext.delete(session)
                }
            }
            
            if let memos = book.memos {
                for memo in memos {
                    modelContext.delete(memo)
                }
            }
            
            // 현재 인덱스 조정
            if currentIndex >= books.count - 1 && currentIndex > 0 {
                currentIndex -= 1
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

// MARK: - Book Card View
struct BookCardView: View {
    let book: Book
    let onDelete: () -> Void
    @Binding var showDetails: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 24) {
                
                // 책 표지
                bookCoverView
                    .padding(.top, 40)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showDetails.toggle()
                        }
                    }
                
                // 책 제목 (항상 표시)
                Text(book.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 20)
                
                // 상세 정보 (아이콘 + 정보)
                if showDetails {
                    infoIconsView
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // 액션 버튼 (상세 보기일 때만)
                if showDetails {
                    actionButtonsView
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Book Cover
    private var bookCoverView: some View {
        Group {
            if let imagePath = book.imagePath,
               let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let imageURL = documentsDirectory.appendingPathComponent(imagePath)
                if let imageData = try? Data(contentsOf: imageURL),
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 240, height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                } else {
                    placeholderCover
                }
            } else {
                placeholderCover
            }
        }
    }
    
    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 240, height: 340)
            .overlay {
                Image(systemName: "book.closed")
                    .font(.system(size: 80))
                    .foregroundStyle(.white.opacity(0.5))
            }
    }
    
    // MARK: - Info Icons
    private var infoIconsView: some View {
        HStack(spacing: 28) {
            
            // 작가
            VStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text(book.author)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 페이지 정보
            VStack(spacing: 6) {
                Image(systemName: "book.pages")
                    .font(.title3)
                    .foregroundColor(.purple)
                Text("\(book.currentPage)/\(book.totalPages)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 총 시간
            VStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.title3)
                    .foregroundColor(.orange)
                Text(totalReadingTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Action Buttons View
    private var actionButtonsView: some View {
        HStack(spacing: 20) {
            NavigationLink(destination: ReadingTimerView(book: book)) {
                ActionButton(icon: "play.fill", title: "Read", color: .blue)
            }
            
            NavigationLink(destination: MemoTimelineView(book: book)) {
                ActionButton(icon: "note.text", title: "Memos", color: .orange)
            }
            
            Button { onDelete() } label: {
                ActionButton(icon: "trash", title: "Delete", color: .red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
    
    // MARK: - Computed Properties
    private var totalReadingTime: String {
        guard let sessions = book.sessions else { return "0m" }
        let totalSeconds = sessions.reduce(0) { $0 + (Double($1.duration ?? 0)) }
        
        let hours = Int(totalSeconds / 3600)
        let minutes = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(color.opacity(0.15))
                )
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}
