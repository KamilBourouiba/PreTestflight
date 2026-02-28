import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    var body: some View {
        Form {
            Toggle("Show completed", isOn: $viewModel.showCompleted)
                .accessibilityIdentifier("settings_showCompleted")
        }
        .navigationTitle("Settings")
        .accessibilityIdentifier("settingsScreen")
    }
}
