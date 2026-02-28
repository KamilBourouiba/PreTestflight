import Foundation

/// Syncs notes with backend (project_b only).
final class APIClient {
    func fetchNotes() async throws -> [NoteItem] { [] }
    func saveNote(_ note: NoteItem) async throws { }
}
