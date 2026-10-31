import SwiftUI
import SwiftData
import PhotosUI

struct EditMemoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let memo: PageMemo
    
    @State private var draftMemo: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @FocusState private var isInputFocused: Bool
    
    // MARK: - 사진 관련 상태
    @State private var selectedImage: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCamera = false
    
    @ObservedObject private var themeManager = ThemeManager.shared
    var paperColor: Color { themeManager.currentTheme.paperColor(isDark: colorScheme == .dark) }
    var inkColor: Color { themeManager.currentTheme.inkColor(isDark: colorScheme == .dark) }
    
    var body: some View {
        NavigationStack {
            ZStack {
                paperColor.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "xmark").font(.title2).foregroundStyle(inkColor) }
                        Spacer()
                        Text("edit memo.").font(.custom("ChalkboardSE-Bold", size: 20)).foregroundStyle(inkColor)
                        Spacer()
                        Button { saveMemo() } label: {
                            Image(systemName: "checkmark").font(.title2)
                                .foregroundStyle(isFormValid ? inkColor : inkColor.opacity(0.3))
                        }
                        .disabled(!isFormValid)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            
                            HStack {
                                let isEbook = memo.book?.isEbook ?? false
                                Text(isEbook ? "progress (%)." : "pages.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                Spacer()
                                Text(isEbook ? "\((Double(memo.startPage) / 100).formatted(.percent.precision(.fractionLength(0)))) - \((Double(memo.endPage) / 100).formatted(.percent.precision(.fractionLength(0))))" : "p. \(memo.startPage) - \(memo.endPage)").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor.opacity(0.8))
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                            
                            // MARK: - ⭐️ 사진 수정/삭제 뷰
                            VStack(alignment: .leading, spacing: 12) {
                                Text("photo.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor).padding(.horizontal, 24)
                                
                                if let selectedImage {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: selectedImage)
                                            .resizable().scaledToFill().frame(height: 200).frame(maxWidth: .infinity)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                            .clipped()
                                        
                                        Button { self.selectedImage = nil } label: {
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(inkColor).background(Circle().fill(paperColor)).font(.title2)
                                        }
                                        .padding(8)
                                    }.padding(.horizontal, 24)
                                } else {
                                    Rectangle().fill(Color.clear).frame(height: 120)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                                        .overlay(Image(systemName: "camera.dashed").font(.largeTitle).foregroundStyle(inkColor.opacity(0.3)))
                                        .padding(.horizontal, 24)
                                }
                                
                                HStack(spacing: 12) {
                                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                        HStack { Image(systemName: "photo"); Text("gallery") }
                                        .font(.custom("ChalkboardSE-Regular", size: 14)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(inkColor).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                    }
                                    
                                    Button { showCamera = true } label: {
                                        HStack { Image(systemName: "camera"); Text("camera") }
                                        .font(.custom("ChalkboardSE-Regular", size: 14)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(inkColor).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                    }
                                }.padding(.horizontal, 24)
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("thoughts.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor).padding(.horizontal, 24)
                                ZStack {
                                    VStack(spacing: 28) { ForEach(0..<15, id: \.self) { _ in Divider().background(inkColor.opacity(0.08)) } }.padding(.top, 20)
                                    TextEditor(text: $draftMemo).focused($isInputFocused).font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor).scrollContentBackground(.hidden).padding(12).lineSpacing(6)
                                }
                                .frame(minHeight: 280).background(paperColor).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5)).padding(.horizontal, 24)
                            }
                            Spacer().frame(height: 40)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .toolbar { ToolbarItem(placement: .keyboard) { HStack { Spacer(); Button("Done") { isInputFocused = false }.font(.custom("ChalkboardSE-Bold", size: 16)).foregroundStyle(inkColor) } } }
            .onAppear {
                draftMemo = memo.memo
                if let data = memo.imageData { self.selectedImage = UIImage(data: data) }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        selectedImage = image
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) { ImagePicker(image: $selectedImage, sourceType: .camera).ignoresSafeArea() }
            .alert("Oops", isPresented: $showError) { Button("OK", role: .cancel) { } } message: { Text(errorMessage) }
        }
    }
    
    private var isFormValid: Bool {
        let textNotEmpty = !draftMemo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return textNotEmpty || selectedImage != nil
    }
    
    private func saveMemo() {
        let imageData: Data? = selectedImage.flatMap { image in
            let scale = 800 / image.size.width
            let size = CGSize(width: 800, height: image.size.height * scale)
            let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            return resized.jpegData(compressionQuality: 0.7)
        }
        
        memo.updateMemo(draftMemo, imageData: imageData)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save memo"
            showError = true
        }
    }
}
