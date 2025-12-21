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
    
    // iPad 감지
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
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
                                    showDetails: $showDetails,
                                    isIPad: isIPad
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
                .font(.system(size: isIPad ? 120 : 80))
                .foregroundStyle(.blue.opacity(0.5))
            
            Text("No Books Yet")
                .font(isIPad ? .largeTitle : .title)
                .fontWeight(.bold)
            
            Text("Start your reading journey by adding a book")
                .font(isIPad ? .title3 : .body)
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
                    .font(isIPad ? .body : .caption)
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
            // 관련 데이터 삭제
            book.sessions?.forEach { modelContext.delete($0) }
            book.memos?.forEach { modelContext.delete($0) }
            
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
    let isIPad: Bool
    
    // 디바이스별 크기 설정
    private var coverSize: CGSize {
        if isIPad {
            return CGSize(width: 480, height: 680)  // iPad: 화면에 맞게 크게
        } else {
            return CGSize(width: 280, height: 400)  // iPhone: 기존보다 크게
        }
    }
    
    private var topPadding: CGFloat {
        isIPad ? 60 : 40
    }
    
    private var horizontalPadding: CGFloat {
        isIPad ? 48 : 32
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: isIPad ? 32 : 24) {
                    
                    // 책 표지
                    bookCoverView
                        .padding(.top, topPadding)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showDetails.toggle()
                            }
                        }
                    
                    // 책 제목 (항상 표시)
                    Text(book.title)
                        .font(isIPad ? .largeTitle : .title2)
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
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, horizontalPadding)
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }
    
    // MARK: - Book Cover
    private var bookCoverView: some View {
        Group {
            if let imageData = book.coverImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: coverSize.width, height: coverSize.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: isIPad ? 24 : 20))
                    .shadow(color: .black.opacity(0.3), radius: isIPad ? 30 : 20, x: 0, y: isIPad ? 15 : 10)
            } else {
                placeholderCover
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: isIPad ? 24 : 20)
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: coverSize.width, height: coverSize.height)
            .overlay {
                Image(systemName: "book.closed")
                    .font(.system(size: isIPad ? 120 : 80))
                    .foregroundStyle(.white.opacity(0.5))
            }
    }
    
    // MARK: - Info Icons
    private var infoIconsView: some View {
        HStack(spacing: isIPad ? 40 : 28) {
            
            // 작가
            VStack(spacing: isIPad ? 8 : 6) {
                Image(systemName: "person.fill")
                    .font(isIPad ? .title2 : .title3)
                    .foregroundColor(.blue)
                Text(book.author)
                    .font(isIPad ? .body : .caption)
                    .foregroundColor(.secondary)
            }
            
            // 페이지 정보
            VStack(spacing: isIPad ? 8 : 6) {
                Image(systemName: "book.pages")
                    .font(isIPad ? .title2 : .title3)
                    .foregroundColor(.purple)
                Text("\(book.currentPage)/\(book.totalPages)")
                    .font(isIPad ? .body : .caption)
                    .foregroundColor(.secondary)
            }
            
            // 총 시간
            VStack(spacing: isIPad ? 8 : 6) {
                Image(systemName: "clock")
                    .font(isIPad ? .title2 : .title3)
                    .foregroundColor(.orange)
                Text(totalReadingTime)
                    .font(isIPad ? .body : .caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Action Buttons View
    private var actionButtonsView: some View {
        HStack(spacing: isIPad ? 32 : 20) {
            NavigationLink(destination: ReadingTimerView(book: book)) {
                ActionButton(icon: "play.fill", title: "Read", color: .blue, isIPad: isIPad)
            }
            
            NavigationLink(destination: MemoTimelineView(book: book)) {
                ActionButton(icon: "note.text", title: "Memos", color: .orange, isIPad: isIPad)
            }
            
            Button { onDelete() } label: {
                ActionButton(icon: "trash", title: "Delete", color: .red, isIPad: isIPad)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, isIPad ? 24 : 16)
    }
    
    // MARK: - Computed Properties
    private var totalReadingTime: String {
        guard let sessions = book.sessions else { return "0m" }
        let totalSeconds = sessions.reduce(0) { $0 + $1.duration }

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
    let isIPad: Bool
    
    private var buttonSize: CGFloat {
        isIPad ? 80 : 60
    }
    
    var body: some View {
        VStack(spacing: isIPad ? 12 : 8) {
            Image(systemName: icon)
                .font(isIPad ? .title : .title2)
                .foregroundStyle(color)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(color.opacity(0.15))
                )
            
            Text(title)
                .font(isIPad ? .body : .caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}
