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

            UpdatesSettingsPane()
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .scenePadding()
        .frame(width: 520, height: 350)
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
                Text("Cached CSV files can be regenerated from FIRST. Team tags and saved API credentials are not removed.")
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

private struct UpdatesSettingsPane: View {
    @State private var updater = AppUpdateController()

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed version") {
                    Text(updater.currentVersionText)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let release = updater.latestRelease {
                    LabeledContent("Latest version") {
                        Text(release.version.description)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("Version")
            }

            Section {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if updater.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: statusSymbol)
                            .foregroundStyle(statusColor)
                    }

                    Text(updater.statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                HStack {
                    Link("View Releases", destination: releasePageURL)

                    Spacer()

                    Button(updater.buttonTitle) {
                        Task {
                            await updater.performUpdate()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(updater.isWorking)
                }
            } header: {
                Text("Software Update")
            } footer: {
                Text("Updates are downloaded from the official GitHub release, verified with SHA-256, and opened with the macOS installer.")
            }
        }
        .formStyle(.grouped)
    }

    private var releasePageURL: URL {
        updater.latestRelease?.releasePageURL ?? AppUpdateService.releasesPageURL
    }

    private var statusSymbol: String {
        switch updater.state {
        case .upToDate:
            return "checkmark.circle.fill"
        case .installerOpened:
            return "arrow.down.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .idle, .checking, .downloading:
            return "info.circle"
        }
    }

    private var statusColor: Color {
        switch updater.state {
        case .upToDate:
            return .green
        case .installerOpened:
            return .accentColor
        case .failed:
            return .orange
        case .idle, .checking, .downloading:
            return .secondary
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
                Text("Credentials are stored in private app data on this Mac. The token file is readable only by your macOS user, and unchanged credentials are never rewritten.")
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
