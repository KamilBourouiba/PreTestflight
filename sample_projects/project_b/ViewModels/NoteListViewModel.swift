import Foundation
import Combine

final class NoteListViewModel: ObservableObject {
    @Published var notes: [NoteItem] = []
    @Published var searchText: String = ""

    var filteredNotes: [NoteItem] {
        guard !searchText.isEmpty else { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    func addNote(title: String, body: String) {
        notes.append(NoteItem(id: UUID(), title: title, body: body, createdAt: Date()))
    }
}
