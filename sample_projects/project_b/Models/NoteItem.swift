import Foundation

struct NoteItem: Identifiable {
    let id: UUID
    var title: String
    var body: String
    var createdAt: Date
}
