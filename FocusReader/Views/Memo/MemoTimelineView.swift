//
//  MemoTimelineView.swift
//  FocusReader
//
//  Created by JeaminPark on 12/10/25.
//

import SwiftUI
import SwiftData

struct MemoTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let book: Book
    
    @Query private var allMemos: [PageMemo]
    @State private var editingMemo: PageMemo?
    @State private var scrollToPage: Int?
    @State private var refreshID = UUID()
    
    init(book: Book) {
        self.book = book
        let bookID = book.id
        _allMemos = Query(
            filter: #Predicate<PageMemo> { memo in
                memo.book?.id == bookID
            },
            sort: \PageMemo.startPage,
            order: .forward
        )
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AdaptiveTopBannerView()
                Group {
                    if allMemos.isEmpty {
                        ContentUnavailableView(
                            "No Memos",
                            systemImage: "note.text",
                            description: Text("No memos yet")
                        )
                    } else {
                        List {
                            ForEach(allMemos) { memo in
                                MemoCardView(
                                    memo: memo,
                                    onEdit: {
                                        editingMemo = memo
                                    }
                                )
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteMemo(memo)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                .id(refreshID)
                .navigationTitle("\(book.title) - Memos")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $editingMemo) { memo in
                    EditMemoView(memo: memo)
                }
                .onAppear {
                    print("MemoTimelineView appeared")
                    print("Book: \(book.title), ID: \(book.id)")
                    print("Memos count: \(allMemos.count)")
                }
                .task {
                    // task modifier는 뷰가 완전히 로드된 후 실행됨
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2초
                    refreshID = UUID()
                    print("After refresh - Memos count: \(allMemos.count)")
                }

                // Bottom banner
                AdaptiveBottomBannerView()
            }
        }
    }
    
    private func deleteMemo(_ memo: PageMemo) {
        withAnimation {
            modelContext.delete(memo)
            do {
                try modelContext.save()
                refreshID = UUID() // 삭제 후 UI 새로고침
            } catch {
                print("Failed to delete memo: \(error)")
            }
        }
    }
}

struct MemoCardView: View {
    let memo: PageMemo
    let onEdit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pages \(memo.startPage) - \(memo.endPage)")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Text(memo.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
            }
            
            Text(memo.memo)
                .font(.body)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.vertical, 4)
    }
}

