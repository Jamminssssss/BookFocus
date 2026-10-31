import SwiftUI
import SwiftData

struct MemoTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @ObservedObject private var themeManager = ThemeManager.shared
    var paperColor: Color { themeManager.currentTheme.paperColor(isDark: colorScheme == .dark) }
    var inkColor: Color { themeManager.currentTheme.inkColor(isDark: colorScheme == .dark) }
    
    let book: Book
    @Query private var allMemos: [PageMemo]
    @State private var editingMemo: PageMemo?
    @State private var showAddMemo = false
    
    // 펼쳐볼 공책(읽기 모드) 상태 관리
    @State private var selectedMemoForReading: PageMemo?
    
    init(book: Book) {
        self.book = book
        let bookID = book.id
        _allMemos = Query(filter: #Predicate<PageMemo> { memo in memo.book?.id == bookID }, sort: \PageMemo.startPage, order: .forward)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                paperColor.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.title2).foregroundStyle(inkColor) }
                        Spacer()
                        Text("memos.").font(.custom("ChalkboardSE-Bold", size: 20)).foregroundStyle(inkColor)
                        Spacer()
                        Button { showAddMemo = true } label: { Image(systemName: "plus").font(.title2).foregroundStyle(inkColor) }
                    }.padding(.horizontal, 24).padding(.vertical, 16)
                    
                    Group {
                        if allMemos.isEmpty {
                            VStack(spacing: 16) {
                                Spacer()
                                Image(systemName: "book.closed").font(.system(size: 60, weight: .ultraLight)).foregroundStyle(inkColor.opacity(0.3))
                                Text("no notebooks added yet.").font(.custom("ChalkboardSE-Regular", size: 18)).foregroundColor(inkColor.opacity(0.7))
                                Spacer()
                            }
                        } else {
                            List {
                                ForEach(allMemos) { memo in
                                    AnalogNotebookCardView(
                                        memo: memo,
                                        isEbook: book.isEbook,
                                        inkColor: inkColor,
                                        paperColor: paperColor,
                                        onOpen: {
                                            selectedMemoForReading = memo
                                        },
                                        onEdit: { editingMemo = memo }
                                    )
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) { deleteMemo(memo) } label: { Label("Delete", systemImage: "trash") }
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(item: $editingMemo) { memo in EditMemoView(memo: memo) }
            .fullScreenCover(isPresented: $showAddMemo) { AddMemoView(book: book) }
            // ⭐️ 모달 오버레이 대신 Full Screen Cover로 전체 화면 표시
            .fullScreenCover(item: $selectedMemoForReading) { memoToRead in
                OpenNotebookView(
                    memo: memoToRead,
                    isEbook: book.isEbook,
                    onClose: {
                        selectedMemoForReading = nil
                    },
                    onEdit: {
                        selectedMemoForReading = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            editingMemo = memoToRead
                        }
                    }
                )
            }
        }
    }
    
    private func deleteMemo(_ memo: PageMemo) {
        withAnimation {
            modelContext.delete(memo)
            try? modelContext.save()
        }
    }
}
