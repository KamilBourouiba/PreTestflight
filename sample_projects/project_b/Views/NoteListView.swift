import SwiftUI

struct NoteListView: View {
    @StateObject private var viewModel = NoteListViewModel()

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.filteredNotes) { note in
                    VStack(alignment: .leading) {
                        Text(note.title)
                            .accessibilityIdentifier("noteTitle_\(note.id)")
                        Text(note.body)
                            .font(.caption)
                            .accessibilityIdentifier("noteBody_\(note.id)")
                    }
                }
            }
            .navigationTitle("Notes")
            .searchable(text: $viewModel.searchText)
            .accessibilityIdentifier("noteList")
        }
    }
}
