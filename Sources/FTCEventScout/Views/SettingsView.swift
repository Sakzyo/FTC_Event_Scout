import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    let updater: AppUpdateController

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

            UpdatesSettingsPane(updater: updater)
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .scenePadding()
        .frame(width: 520, height: 450)
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
                Picker("OPR leaders", selection: $model.oprChartLayout) {
                    ForEach(OPRChartLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Rankings")
            } footer: {
                Text("All Metrics stacks a top-10 chart for every OPR metric. Single Metric shows one metric at a time with its leader and every team.")
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
    @Bindable var updater: AppUpdateController

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed version") {
                    Text(updater.currentVersionText)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Version")
            }

            Section {
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                    .disabled(updater.unavailableReason != nil)
                Toggle("Download and install updates automatically", isOn: $updater.automaticallyDownloadsUpdates)
                    .disabled(updater.unavailableReason != nil || !updater.automaticallyChecksForUpdates)

                if let reason = updater.unavailableReason {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Link("View Releases", destination: AppUpdateController.releasesPageURL)
                    Spacer()
                    Button("Check for Updates…", action: updater.checkForUpdates)
                        .buttonStyle(.borderedProminent)
                        .disabled(!updater.canCheckForUpdates)
                }
            } header: {
                Text("Software Update")
            } footer: {
                Text("Updates are downloaded and signature-verified inside the app. Install and Relaunch applies an update immediately; automatic updates install when you quit. Your saved credentials, tags, and preferences are preserved.")
            }
        }
        .formStyle(.grouped)
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
