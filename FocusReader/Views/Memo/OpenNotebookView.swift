import SwiftUI

struct OpenNotebookView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale // Add this line
    @ObservedObject private var themeManager = ThemeManager.shared
    
    var paperColor: Color { themeManager.currentTheme.paperColor(isDark: colorScheme == .dark) }
    var inkColor: Color { themeManager.currentTheme.inkColor(isDark: colorScheme == .dark) }
    
    let memo: PageMemo
    let isEbook: Bool
    let onClose: () -> Void
    var onEdit: (() -> Void)? = nil
    
    @State private var renderedImage: UIImage? = nil
    @State private var showShareSheet = false
    
    // MARK: - 사진 뷰어용 상태 변수
    @State private var uiImage: UIImage? = nil
    @State private var showFullScreen = false
    
    var body: some View {
        ZStack {
            paperColor.ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    Button(action: onClose) { Image(systemName: "xmark").font(.title2).foregroundStyle(inkColor).padding(8) }
                    Spacer()
                    Text(memo.createdAt, style: .date).font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                    Spacer()
                    HStack(spacing: 16) {
                        Button { shareQuoteCard() } label: { Image(systemName: "square.and.arrow.up").font(.title2).foregroundStyle(inkColor) }
                        if let onEdit = onEdit {
                            Button(action: onEdit) { Image(systemName: "pencil").font(.title2).foregroundStyle(inkColor) }
                        } else { Color.clear.frame(width: 24, height: 24) }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        HStack {
                            Text(isEbook ? "progress (%)." : "pages.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                            Spacer()
                            Text(isEbook ? "\((Double(memo.startPage) / 100).formatted(.percent.precision(.fractionLength(0)))) - \((Double(memo.endPage) / 100).formatted(.percent.precision(.fractionLength(0))))" : "p. \(memo.startPage) - \(memo.endPage)").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor.opacity(0.8))
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        
                        // MARK: - 기록된 사진 영역
                        if let uiImage {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("captured page.")
                                    .font(.custom("ChalkboardSE-Bold", size: 18))
                                    .foregroundStyle(inkColor)
                                    .padding(.horizontal, 24)
                                
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxHeight: 300)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                    .padding(.horizontal, 24)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        showFullScreen = true
                                    }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("thoughts.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor).padding(.horizontal, 24)
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 28) { ForEach(0..<15, id: \.self) { _ in Divider().background(inkColor.opacity(0.08)) } }.padding(.top, 20)
                                ScrollView(showsIndicators: false) { HandwritingTextView(fullText: memo.memo, font: .custom("ChalkboardSE-Regular", size: 16), color: inkColor, speed: 0.05, initialDelay: 0.1, playSound: true).padding(16) }
                            }
                            .frame(minHeight: 280).background(paperColor).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5)).padding(.horizontal, 24)
                        }
                        Spacer().frame(height: 40)
                    }
                }
            }
        }
        .onAppear {
            if let data = memo.imageData { self.uiImage = UIImage(data: data) }
        }
        .sheet(isPresented: $showShareSheet) {
            if let imageToShare = renderedImage { ShareSheet(activityItems: [imageToShare]) }
        }
        // ⭐️ 풀스크린 모달 띄우기
        .fullScreenCover(isPresented: $showFullScreen) {
            if let uiImage { FullScreenImageView(image: uiImage, paperColor: paperColor, inkColor: inkColor) }
        }
    }
    
    @MainActor private func shareQuoteCard() {
        let cardView = QuoteCardRenderView(
            memoText: memo.memo,
            bookTitle: memo.book?.title ?? "Unknown Title",
            bookAuthor: memo.book?.author ?? "Unknown Author",
            paperColor: paperColor,
            inkColor: inkColor
        )
        
        let renderer = ImageRenderer(content: cardView)
        renderer.scale = displayScale // Update this line
        
        if let uiImage = renderer.uiImage {
            self.renderedImage = uiImage
            self.showShareSheet = true
        }
    }
}
