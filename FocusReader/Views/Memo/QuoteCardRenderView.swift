import SwiftUI
import UIKit

// MARK: - 인스타그램/SNS 공유용 카드 뷰
struct QuoteCardRenderView: View {
    let memoText: String
    let bookTitle: String
    let bookAuthor: String
    let paperColor: Color
    let inkColor: Color
    var attachedImage: UIImage? = nil // ⭐️ 추가: 첨부된 이미지를 받을 수 있게 함
    
    var body: some View {
        ZStack {
            // 배경 종이 질감
            paperColor
            
            VStack(alignment: .leading, spacing: 30) {
                
                // ⭐️ 첨부된 이미지가 있을 경우 상단에 배치
                if let attachedImage = attachedImage {
                    Image(uiImage: attachedImage)
                        .resizable()
                        .scaledToFill()
                        // 텍스트가 없으면 이미지를 더 크게, 텍스트가 있으면 적당한 크기로
                        .frame(height: memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 650 : 450)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(inkColor, lineWidth: 6))
                        .clipped()
                } else {
                    // 이미지가 없을 때만 기존처럼 큰 따옴표 표시
                    Image(systemName: "quote.opening")
                        .font(.system(size: 80, weight: .light))
                        .foregroundStyle(inkColor.opacity(0.3))
                }
                
                // 메모 본문 (텍스트가 있을 때만 렌더링)
                if !memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(memoText)
                        .font(.custom("ChalkboardSE-Regular", size: attachedImage != nil ? 35 : 45)) // 이미지가 있으면 폰트 사이즈 살짝 축소
                        .foregroundStyle(inkColor)
                        .lineSpacing(16)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.5)
                }
                
                Spacer()
                
                // 하단 책 정보 및 브랜딩
                VStack(alignment: .trailing, spacing: 12) {
                    HStack {
                        Spacer()
                        Text("- \(bookTitle)")
                            .font(.custom("ChalkboardSE-Bold", size: 32))
                            .foregroundStyle(inkColor)
                    }
                    
                    Text(bookAuthor)
                        .font(.custom("ChalkboardSE-Regular", size: 26))
                        .foregroundStyle(inkColor.opacity(0.7))
                    
                    Spacer().frame(height: 30)
                    
                    // 워터마크
                    HStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "book.closed")
                        Text("BookFocus")
                    }
                    .font(.custom("ChalkboardSE-Bold", size: 22))
                    .foregroundStyle(inkColor.opacity(0.4))
                }
            }
            .padding(80)
            .padding(.top, 40)
        }
        .frame(width: 1080, height: 1080)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(inkColor, lineWidth: 8)
                .padding(40)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(inkColor.opacity(0.5), style: StrokeStyle(lineWidth: 3, dash: [15, 15]))
                .padding(55)
        )
    }
}

// MARK: - iOS 네이티브 공유 시트 래퍼
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
