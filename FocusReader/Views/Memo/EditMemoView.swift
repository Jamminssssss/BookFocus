//
//  EditMemoView.swift
//  FocusReader
//
//  Created by JeaminPark on 12/10/25.
//

import SwiftUI
import SwiftData

struct EditMemoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var memo: PageMemo
    
    @State private var editedMemo: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Pages \(memo.startPage) - \(memo.endPage)")
                        .font(.headline)
                } header: {
                    Text("Page Range")
                }
                
                Section {
                    TextEditor(text: $editedMemo)
                        .frame(minHeight: 200)
                } header: {
                    Text("Memo")
                }
            }
            .navigationTitle("Edit Memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMemo()
                    }
                }
            }
            .onAppear {
                editedMemo = memo.memo
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveMemo() {
        memo.memo = editedMemo
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save memo: \(error.localizedDescription)"
            showError = true
        }
    }
}

