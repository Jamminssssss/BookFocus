import SwiftUI

struct GoodreadsImportProgressView: View {
    @ObservedObject var manager: GoodreadsImportManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var paperColor: Color { colorScheme == .dark ? Color.black : Color(red: 0.98, green: 0.97, blue: 0.95) }
    var inkColor: Color { colorScheme == .dark ? Color.white : Color.black }
    
    var body: some View {
        ZStack {
            paperColor.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Text("goodreads import.")
                    .font(.custom("ChalkboardSE-Bold", size: 24))
                    .foregroundStyle(inkColor)
                    .padding(.top, 24)
                
                if manager.isImporting {
                    ProgressView(value: Double(manager.processedBooks), total: Double(manager.totalBooks > 0 ? manager.totalBooks : 1))
                        .tint(inkColor)
                        .padding(.horizontal, 40)
                    
                    Text("Processing \(manager.processedBooks) of \(manager.totalBooks)...")
                        .font(.custom("ChalkboardSE-Regular", size: 16))
                        .foregroundStyle(inkColor)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(inkColor)
                    
                    Text("Import Complete!")
                        .font(.custom("ChalkboardSE-Bold", size: 20))
                        .foregroundStyle(inkColor)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    statRow(icon: "book.closed", label: "Imported Successfully", value: manager.importedCount)
                    statRow(icon: "doc.on.doc", label: "Duplicates Skipped", value: manager.duplicateCount)
                    statRow(icon: "exclamationmark.triangle", label: "Failed Rows", value: manager.failedCount)
                    statRow(icon: "magnifyingglass", label: "Not Found in API", value: manager.notFoundCount)
                }
                .padding(20)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkColor, lineWidth: 1.5))
                .padding(.horizontal, 24)
                
                if !manager.isImporting {
                    Button {
                        dismiss()
                    } label: {
                        Text("done")
                            .font(.custom("ChalkboardSE-Bold", size: 18))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundStyle(inkColor)
                            .overlay(RoundedRectangle(cornerRadius: 25).stroke(inkColor, lineWidth: 1.5))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
                Spacer()
            }
        }
        .interactiveDismissDisabled(manager.isImporting)
    }
    
    private func statRow(icon: String, label: String, value: Int) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 24)
            Text(label).font(.custom("ChalkboardSE-Regular", size: 16))
            Spacer()
            Text("\(value)").font(.custom("ChalkboardSE-Bold", size: 18))
        }
        .foregroundStyle(inkColor)
    }
}
