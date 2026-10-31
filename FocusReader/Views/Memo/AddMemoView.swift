import SwiftUI
import SwiftData
import PhotosUI

struct AddMemoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let book: Book
    
    @State private var startPage: String = ""
    @State private var endPage: String = ""
    @State private var memoText: String = ""
    
    // MARK: - 사진 관련 상태
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showCamera = false
    
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @FocusState private var isInputFocused: Bool
    
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
                        Text("add memo.").font(.custom("ChalkboardSE-Bold", size: 20)).foregroundStyle(inkColor)
                        Spacer()
                        Button { saveMemo() } label: { Image(systemName: "checkmark").font(.title2).foregroundStyle(isFormValid ? inkColor : inkColor.opacity(0.3)) }.disabled(!isFormValid)
                    }.padding(.horizontal, 24).padding(.vertical, 16)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 6) { Text(book.title).font(.custom("ChalkboardSE-Bold", size: 22)).foregroundStyle(inkColor); Text(book.author).font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor.opacity(0.7)) }.padding(.horizontal, 24).padding(.top, 8)
                            
                            VStack(alignment: .leading, spacing: 16) {
                                Text(book.isEbook ? "progress (%)." : "pages.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                HStack(spacing: 16) {
                                    TextField("start", text: $startPage).keyboardType(.numberPad).focused($isInputFocused).textFieldStyle(.plain).font(.custom("ChalkboardSE-Regular", size: 16)).multilineTextAlignment(.center).foregroundStyle(inkColor).padding(16).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                    Text("-").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                    TextField("end", text: $endPage).keyboardType(.numberPad).focused($isInputFocused).textFieldStyle(.plain).font(.custom("ChalkboardSE-Regular", size: 16)).multilineTextAlignment(.center).foregroundStyle(inkColor).padding(16).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                }
                            }.padding(.horizontal, 24)
                            
                            // MARK: - ⭐️ 바로 이 부분이 사진을 추가하는 기능 뷰입니다.
                            VStack(alignment: .leading, spacing: 16) {
                                Text("photo.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor)
                                
                                if let selectedImage {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: selectedImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 200)
                                            .frame(maxWidth: .infinity)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                            .clipped()
                                        
                                        Button { self.selectedImage = nil } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title2)
                                                .foregroundStyle(inkColor)
                                                .background(Circle().fill(paperColor))
                                        }
                                        .padding(8)
                                    }
                                } else {
                                    Rectangle().fill(Color.clear).frame(height: 120)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                                        .overlay(Image(systemName: "camera.dashed").font(.largeTitle).foregroundStyle(inkColor.opacity(0.3)))
                                }
                                
                                HStack(spacing: 12) {
                                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                        HStack(spacing: 6) { Image(systemName: "photo"); Text("gallery") }
                                        .font(.custom("ChalkboardSE-Regular", size: 14))
                                        .frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(inkColor).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                    }
                                    
                                    Button { showCamera = true } label: {
                                        HStack(spacing: 6) { Image(systemName: "camera"); Text("camera") }
                                        .font(.custom("ChalkboardSE-Regular", size: 14))
                                        .frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(inkColor).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                                    }
                                }
                            }.padding(.horizontal, 24)
                            
                            VStack(alignment: .leading, spacing: 16) { Text("thoughts.").font(.custom("ChalkboardSE-Bold", size: 18)).foregroundStyle(inkColor); TextEditor(text: $memoText).focused($isInputFocused).font(.custom("ChalkboardSE-Regular", size: 16)).foregroundStyle(inkColor).scrollContentBackground(.hidden).padding(12).frame(minHeight: 180).overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5)) }.padding(.horizontal, 24)
                            Spacer().frame(height: 40)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .toolbar { ToolbarItem(placement: .keyboard) { HStack { Spacer(); Button("Done") { isInputFocused = false }.font(.custom("ChalkboardSE-Bold", size: 16)).foregroundStyle(inkColor) } } }
            .onChange(of: selectedPhoto) { _, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        selectedImage = image
                    }
                }
            }
            // 카메라 띄우기
            .fullScreenCover(isPresented: $showCamera) { ImagePicker(image: $selectedImage, sourceType: .camera).ignoresSafeArea() }
            .alert("Oops", isPresented: $showError) { Button("OK", role: .cancel) { } } message: { Text(errorMessage) }
        }
    }
    
    // 텍스트나 사진 둘 중 하나는 있어야 유효함
    private var isFormValid: Bool {
        guard let s = Int(startPage), let e = Int(endPage) else { return false }
        let minVal = book.isEbook ? 0 : 1
        let textNotEmpty = !memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return s >= minVal && e >= s && e <= max(minVal, book.totalPages) && (textNotEmpty || selectedImage != nil)
    }
    
    private func saveMemo() {
        guard let start = Int(startPage), let end = Int(endPage) else { return }
        
        let imageData: Data? = selectedImage.flatMap { image in
            let scale = 800 / image.size.width
            let size = CGSize(width: 800, height: image.size.height * scale)
            let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            return resized.jpegData(compressionQuality: 0.7)
        }
        
        let newMemo = PageMemo(startPage: start, endPage: end, memo: memoText, book: book, imageData: imageData)
        modelContext.insert(newMemo)
        
        do { try modelContext.save(); dismiss() }
        catch { errorMessage = "Failed to save memo"; showError = true }
    }
}
