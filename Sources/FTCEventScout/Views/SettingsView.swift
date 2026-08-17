import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsPane(model: model)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            CredentialsSettingsPane(model: model)
                .tabItem {
                    Label("FIRST API", systemImage: "key")
                }
        }
        .scenePadding()
        .frame(width: 520, height: 330)
    }
}

private struct GeneralSettingsPane: View {
    @Bindable var model: AppModel
    @State private var confirmsCacheRemoval = false

    var body: some View {
        Form {
            Section {
                Toggle("Remember the last event code", isOn: $model.rememberLastEvent)
            } header: {
                Text("Startup")
            } footer: {
                Text("The event code and ranking sort preference are stored only on this Mac.")
            }

            Section {
                LabeledContent("Generated event data") {
                    Text("Caches")
                        .foregroundStyle(.secondary)
                }
                Button("Clear Event Cache…", role: .destructive) {
                    confirmsCacheRemoval = true
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Cached CSV files can be regenerated from FIRST. Team tags and Keychain credentials are not removed.")
            }

            if let message = model.settingsMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Clear cached event data?",
            isPresented: $confirmsCacheRemoval
        ) {
            Button("Clear Event Cache", role: .destructive, action: model.clearEventCache)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app will restart its local data service. Event data can be downloaded again.")
        }
    }
}

private struct CredentialsSettingsPane: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $model.username)
                    .textContentType(.username)
                SecureField("Token", text: $model.token)
                    .textContentType(.password)
            } header: {
                Text("FIRST Events API")
            } footer: {
                Text("Credentials are stored in your login Keychain and passed only to the local data service.")
            }

            if let message = model.settingsMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Save and Restart", action: model.saveSettings)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.hasCompleteCredentials)
            }
        }
        .formStyle(.grouped)
    }
}
