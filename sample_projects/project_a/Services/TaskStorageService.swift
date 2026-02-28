import Foundation

/// Persists tasks to UserDefaults for project_a (no network).
final class TaskStorageService {
    private let key = "saved_tasks"
    func save(_ tasks: [TaskItem]) { /* stub */ }
    func load() -> [TaskItem] { [] }
}
