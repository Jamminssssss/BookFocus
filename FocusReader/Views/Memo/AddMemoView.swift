//
//  AddMemoView.swift
//  FocusReader
//
//  Created by JeaminPark on 12/10/25.
//

import SwiftUI
import SwiftData

struct AddMemoView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let book: Book
    
    @State private var startPage: String = ""
    @State private var endPage: String = ""
    @State private var memo: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Start Page", text: $startPage)
                        .keyboardType(.numberPad)
                    TextField("End Page", text: $endPage)
                        .keyboardType(.numberPad)
                    TextEditor(text: $memo)
                        .frame(minHeight: 200)
                } header: {
                    Text("Memo")
                } footer: {
                    Text("Enter the page range and your thoughts.")
                }
                
                Section {
                    Text(book.title)
                        .font(.headline)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Book Information")
                }
            }
            .navigationTitle("Add Memo")
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
                    .disabled(!isValid)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var isValid: Bool {
        !startPage.isEmpty && !endPage.isEmpty && !memo.isEmpty && 
        Int(startPage) != nil && Int(endPage) != nil
    }
    
    private func saveMemo() {
        guard let startPageInt = Int(startPage), let endPageInt = Int(endPage) else {
            errorMessage = "Please enter valid page numbers."
            showError = true
            return
        }
        
        guard startPageInt >= 0 && endPageInt <= book.totalPages && startPageInt <= endPageInt else {
            errorMessage = "Page numbers must be valid and start page must be less than or equal to end page."
            showError = true
            return
        }
        
        let newMemo = PageMemo(startPage: startPageInt, endPage: endPageInt, memo: memo, book: book)
        
        if book.memos == nil {
            book.memos = []
        }
        book.memos?.append(newMemo)
        
        modelContext.insert(newMemo)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save memo: \(error.localizedDescription)"
            showError = true
        }
    }
}

