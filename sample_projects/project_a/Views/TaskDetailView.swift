import SwiftUI

struct TaskDetailView: View {
    let task: TaskItem
    var body: some View {
        VStack {
            Text(task.title)
                .accessibilityIdentifier("taskDetail_title")
            Text(task.isCompleted ? "Done" : "Pending")
                .accessibilityIdentifier("taskDetail_status")
        }
        .navigationTitle("Task")
        .accessibilityIdentifier("taskDetailScreen")
    }
}
