//
//  ContentView.swift
//  FocusReader
//
//  Created by JeaminPark on 12/10/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        BookListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Book.self, ReadingSession.self, PageMemo.self], inMemory: true)
}
