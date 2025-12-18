import SwiftUI
import SwiftData
import PhotosUI

struct AddBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var author: String = ""
    @State private var totalPages: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showCamera = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Book Information") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("Total Pages", text: $totalPages)
                        .keyboardType(.numberPad)
                }
                
                Section("Cover Image") {
                    if let selectedImage = selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                    }
                    
                    HStack(spacing: 16) {
                        // 갤러리에서 선택
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Gallery", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        // 카메라로 촬영
                        Button {
                            showCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .navigationTitle("Add Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveBook() }
                        .disabled(!isValid)
                }
            }
            .onChange(of: selectedPhoto) { oldValue, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(image: $selectedImage, sourceType: .camera)
                    .ignoresSafeArea()
            }
        }
    }
    
    private var isValid: Bool {
        !title.isEmpty && !author.isEmpty && !totalPages.isEmpty && Int(totalPages) != nil
    }
    
    // 🔥 이미지 리사이징 함수 (CloudKit 용량 최적화)
    private func resizeImage(_ image: UIImage, targetWidth: CGFloat = 800) -> UIImage {
        let scale = targetWidth / image.size.width
        let newHeight = image.size.height * scale
        let size = CGSize(width: targetWidth, height: newHeight)
        
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    private func saveBook() {
        guard let pages = Int(totalPages) else { return }

        // 🔥 이미지를 Data로 변환 (리사이징 + 압축)
        let imageData: Data? = selectedImage.flatMap {
            let resized = resizeImage($0, targetWidth: 800)
            return resized.jpegData(compressionQuality: 0.7)
        }

        let newBook = Book(
            title: title,
            author: author,
            totalPages: pages,
            coverImageData: imageData
        )

        modelContext.insert(newBook)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save book: \(error)")
        }
    }
}
