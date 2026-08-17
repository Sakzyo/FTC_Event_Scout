import SwiftUI

struct SettingsView: View {
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
                Text("Credentials are stored in your login keychain and passed only to the local server.")
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
        .scenePadding()
        .frame(width: 520, height: 270)
    }
}
