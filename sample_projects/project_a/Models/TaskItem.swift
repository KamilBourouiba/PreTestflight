import Foundation

struct TaskItem: Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
}
