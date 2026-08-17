import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        content
            .frame(minWidth: 820, minHeight: 560)
            .task {
                model.startIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    EventCodeToolbar(model: model)
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: model.refreshEvent) {
                        Label("Refresh Event", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.isReady || model.eventCode.isEmpty)
                    .help("Refresh Event (⌘R)")

                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Settings (⌘,)")
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.launchState {
        case .idle, .starting:
            LaunchingView()
        case .credentialsRequired:
            CredentialSetupView(model: model)
        case .ready:
            DashboardRootView(model: model)
        case .pythonRequired:
            PythonRequiredView(retry: model.restartBackend)
        case .failed(let message):
            LaunchFailureView(message: message, retry: model.restartBackend)
        }
    }
}

private struct EventCodeToolbar: View {
    @Bindable var model: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("Event code", text: $model.eventCode)
                .frame(width: 160)
                .focused($isFocused)
                .onSubmit(model.loadEvent)
                .disabled(!model.isReady)
                .accessibilityLabel("FTC event code")
                .accessibilityHint("Enter an event code and press Return")

            Button(action: model.loadEvent) {
                Label("Load", systemImage: "arrow.right.circle.fill")
                    .labelStyle(.iconOnly)
            }
            .disabled(!model.isReady || model.eventCode.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Load Event")
        }
        .onChange(of: model.focusToken) { _, _ in
            isFocused = model.isReady
        }
    }
}

private struct PythonRequiredView: View {
    let retry: () -> Void

    private let downloadURL = URL(string: "https://www.python.org/downloads/macos/")!

    var body: some View {
        ContentUnavailableView {
            Label("Python 3 Required", systemImage: "terminal")
        } description: {
            Text("Install the latest Python 3 for macOS. FTC Event Scout finds and uses it automatically; there is no Python setting to configure.")
        } actions: {
            HStack {
                Link(destination: downloadURL) {
                    Label("Download Python 3", systemImage: "arrow.up.right.square")
                }
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct LaunchingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Starting FTC Event Scout", systemImage: "chart.bar.xaxis")
        } description: {
            Text("Preparing the local event data service…")
        } actions: {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Starting local data service")
        }
    }
}

private struct LaunchFailureView: View {
    let message: String
    let retry: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ContentUnavailableView {
            Label("Event Data Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
                .textSelection(.enabled)
        } actions: {
            HStack {
                Button("Open Settings") { openSettings() }
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
