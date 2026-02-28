import Foundation
import Combine

final class TaskListViewModel: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var newTaskTitle: String = ""

    func addTask() {
        guard !newTaskTitle.isEmpty else { return }
        tasks.append(TaskItem(id: UUID(), title: newTaskTitle, isCompleted: false))
        newTaskTitle = ""
    }

    func toggleTask(id: UUID) {
        if let i = tasks.firstIndex(where: { $0.id == id }) {
            tasks[i].isCompleted.toggle()
        }
    }
}
