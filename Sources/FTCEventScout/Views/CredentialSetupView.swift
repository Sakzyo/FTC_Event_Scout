import Foundation
import SwiftUI

struct CredentialSetupView: View {
    private enum Field: Hashable {
        case username
        case token
    }

    @Bindable var model: AppModel
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("Connect to FIRST Events")
                    .font(.largeTitle.weight(.semibold))

                Text("Enter your FIRST Events API credentials to start the scouting dashboard.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text("Username")
                            .gridColumnAlignment(.trailing)
                        TextField("FIRST API username", text: $model.username)
                            .textContentType(.username)
                            .focused($focusedField, equals: .username)
                    }

                    GridRow {
                        Text("Token")
                        SecureField("FIRST API token", text: $model.token)
                            .textContentType(.password)
                            .focused($focusedField, equals: .token)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(8)
            } label: {
                Label("FIRST Events API", systemImage: "key")
            }
            .frame(width: 480)

            Text("Your credentials are stored in your macOS login Keychain and passed only to the local server.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            if let message = model.settingsMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            Button("Save and Continue", action: model.saveCredentialsAndStart)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasCompleteCredentials)
        }
        .padding(40)
        .defaultFocus($focusedField, initialFocus)
    }

    private var initialFocus: Field {
        model.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .username
            : .token
    }
}
