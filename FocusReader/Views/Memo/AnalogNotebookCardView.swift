//
//  AnalogNotebookCardView.swift
//  FocusReader
//
//  Created by JeaminPark on 7/6/26.
//

import SwiftUI

struct AnalogNotebookCardView: View {
    let memo: PageMemo
    let isEbook: Bool
    let inkColor: Color
    let paperColor: Color
    let onOpen: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // ⭐️ 스프링 제본 장식과 텍스트가 겹치지 않도록 좌측 여백 추가
            Spacer()
                .frame(width: 8)
            
            // 공책 표지 정보
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(inkColor.opacity(0.7))
                    
                    Text(isEbook ? "\((Double(memo.startPage) / 100).formatted(.percent.precision(.fractionLength(0)))) - \((Double(memo.endPage) / 100).formatted(.percent.precision(.fractionLength(0))))" : "p. \(memo.startPage) - \(memo.endPage)")
                        .font(.custom("ChalkboardSE-Bold", size: 16))
                        .foregroundStyle(inkColor)
                    
                    Spacer()
                    
                    Text(memo.createdAt, style: .date)
                        .font(.custom("ChalkboardSE-Regular", size: 12))
                        .foregroundColor(inkColor.opacity(0.6))
                    
                    Image(systemName: "pencil")
                        .font(.footnote)
                        .foregroundColor(inkColor)
                        .padding(8)
                        .background(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onEdit()
                        }
                }
                
                // 메모 미리보기 (최대 2줄)
                Text(memo.memo)
                    .font(.custom("ChalkboardSE-Regular", size: 15))
                    .foregroundColor(inkColor.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
        }
        .background(paperColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(inkColor, lineWidth: 1.5))
        // ⭐️ 두 번째 이미지처럼 끝에 캡슐로 묶어 스프링 공책 느낌을 줌
        .overlay(alignment: .leading) {
            VStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in
                    Capsule()
                        .fill(inkColor.opacity(0.7))
                        .frame(width: 12, height: 5)
                        .offset(x: -6)
                }
            }
        }
        .shadow(color: inkColor == .black ? .black.opacity(0.08) : .white.opacity(0.05), radius: 2, x: 3, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
    }
}
