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
                ToolbarItemGroup(placement: .automatic) {
                    SeasonToolbarMenu(model: model)
                    EventCodeToolbar(model: model)
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: model.refreshEvent) {
                        Label("Refresh Event", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.isReady || model.eventCode.isEmpty || model.isManualSourceActive)
                    .help("Refresh Event (⌘R)")

                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Settings (⌘,)")
                }
            }
            .sheet(isPresented: $model.isPresentingNewManualEvent) {
                NewManualEventSheet(model: model)
            }
            .alert(
                "Manual Event Problem",
                isPresented: Binding(
                    get: { model.manualEventError != nil },
                    set: { if !$0 { model.manualEventError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.manualEventError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isManualSourceActive {
            DashboardRootView(model: model)
        } else {
            launchContent
        }
    }

    @ViewBuilder
    private var launchContent: some View {
        switch model.launchState {
        case .idle, .starting:
            LaunchingView()
        case .credentialsRequired:
            CredentialSetupView(model: model)
        case .ready:
            DashboardRootView(model: model)
        case .pythonRequired:
            PythonRequiredView(retry: model.restartBackend, enterManually: model.beginManualEntry)
        case .failed(let message):
            LaunchFailureView(message: message, retry: model.restartBackend, enterManually: model.beginManualEntry)
        }
    }
}

private struct SeasonToolbarMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        if let event = model.activeManualEvent {
            // A manual event's season is fixed when it is created.
            Label(FTCSeason.option(for: event.season).yearRange, systemImage: "calendar")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                // A plain label gets none of a toolbar button's inset, so its icon would
                // touch the edge of the toolbar capsule. Match the season menu's inset.
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .help("\(event.name) uses the \(FTCSeason.option(for: event.season).menuLabel) season")
        } else {
            seasonMenu
        }
    }

    private var seasonMenu: some View {
        Menu {
            Picker("FTC Season", selection: $model.selectedSeason) {
                ForEach(model.availableSeasons) { season in
                    Text(season.menuLabel)
                        .tag(season.startYear)
                }
            }
        } label: {
            Label(model.selectedSeasonOption.yearRange, systemImage: "calendar")
        }
        .help("Choose FTC Season")
        .accessibilityLabel("FTC season, \(model.selectedSeasonOption.yearRange)")
    }
}

private struct EventCodeToolbar: View {
    @Bindable var model: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let event = model.activeManualEvent {
                manualEventButton(event)
            } else {
                eventCodeField
            }
        }
        .onChange(of: model.focusToken) { _, _ in
            isFocused = model.isReady
        }
    }

    private var eventCodeField: some View {
        Group {
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
        .help(model.isReady ? "" : "Add FIRST Events credentials in Settings to load events online")
    }

    /// A manual event has no event code, so the field's place names the open event.
    /// Clicking it returns to FIRST Events with the code field ready for typing.
    private func manualEventButton(_ event: ManualEvent) -> some View {
        Button {
            model.showOnlineEvents()
            // The code field replaces this button on the next update; focus it once it exists.
            Task { @MainActor in model.focusEventCode() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(.tint)
                Text(event.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // As wide as the code field and its Load button, so the toolbar doesn't shift.
            .frame(width: 186, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Plain buttons skip the toolbar inset too; keep the icon off the season label.
        .padding(.leading, 6)
        .help("Showing \(event.name), a manual event. Click to load a FIRST event instead.")
        .accessibilityLabel("Manual event, \(event.name)")
        .accessibilityHint("Switches to FIRST Events so you can enter an event code")
    }
}

private struct PythonRequiredView: View {
    let retry: () -> Void
    let enterManually: () -> Void

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
            Button("Enter Match Data Manually", action: enterManually)
                .buttonStyle(.link)
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
    let enterManually: () -> Void
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
            Button("Enter Match Data Manually", action: enterManually)
                .buttonStyle(.link)
        }
    }
}
