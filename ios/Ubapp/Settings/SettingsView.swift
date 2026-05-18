import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                TextField("Host name", text: $settings.hostName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            } header: {
                Text("Hosting")
            } footer: {
                Text("The name other players see when you host a game. Defaults to \"Host\" if left blank.")
            }

            Section {
                Toggle("Diagnostics", isOn: $settings.diagnosticsEnabled)
            } header: {
                Text("Developer")
            } footer: {
                Text("Shows the host connection log on the hosting screen. Useful for debugging join issues.")
            }
        }
        .scrollContentBackground(.hidden)
        .ubappChrome()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
