import Foundation
import Combine

final class SettingsViewModel: ObservableObject {
    @Published var sortOrder: SortOrder = .date
    @Published var showCompleted: Bool = true
    enum SortOrder { case date, title }
}
