import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            switch model.launchState {
            case .idle, .starting:
                LaunchingView()
            case .credentialsRequired:
                CredentialSetupView(model: model)
            case .ready(let url):
                WebDashboardView(
                    url: url,
                    reloadToken: model.reloadToken,
                    eventCode: model.eventCode,
                    eventLoadToken: model.eventLoadToken
                )
            case .pythonRequired:
                PythonRequiredView(retry: model.restartBackend)
            case .pythonPackagesRequired(let message):
                PythonPackagesRequiredView(message: message, retry: model.restartBackend)
            case .failed(let message):
                LaunchFailureView(message: message, retry: model.restartBackend)
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .task {
            model.startIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                EventCodeToolbar(model: model)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: model.reloadDashboard) {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(!model.isReady)
                .help("Reload Dashboard (⌘R)")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings (⌘,)")
            }
        }
    }
}

private struct EventCodeToolbar: View {
    @Bindable var model: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Event code", text: $model.eventCode)
            .frame(width: 190)
            .focused($isFocused)
            .onSubmit(model.loadEvent)
            .onChange(of: model.focusToken) {
                isFocused = model.isReady
            }
            .disabled(!model.isReady)
            .accessibilityLabel("FTC event code")
            .accessibilityHint("Enter an event code and press Return")
            .help("Enter an event code and press Return (⌘L)")
    }
}

private struct PythonPackagesRequiredView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Python Packages Required", systemImage: "shippingbox")
        } description: {
            Text(message)
                .textSelection(.enabled)
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
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
            Text("Install the latest Python 3 for macOS. FTC Event Scout will find and use it automatically—there is no runtime setting to configure.")
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
            Text("Preparing the local scouting server and dashboard…")
        } actions: {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Starting local server")
        }
    }
}

private struct LaunchFailureView: View {
    let message: String
    let retry: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ContentUnavailableView {
            Label("Local Server Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
                .textSelection(.enabled)
        } actions: {
            HStack {
                Button("Open Settings", action: openSettings)
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
