import SwiftUI

/// Coordinates navigation for project_b (no coordinator in project_a).
final class AppCoordinator: ObservableObject {
    @Published var path: [String] = []
    func openNote(id: UUID) { path.append(id.uuidString) }
}
