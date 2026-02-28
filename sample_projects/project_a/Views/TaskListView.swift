import SwiftUI

struct TaskListView: View {
    @StateObject private var viewModel = TaskListViewModel()

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.tasks) { task in
                    Text(task.title)
                        .accessibilityIdentifier("taskRow_\(task.id)")
                }
            }
            .navigationTitle("Tasks")
            .accessibilityIdentifier("taskList")
        }
    }
}
