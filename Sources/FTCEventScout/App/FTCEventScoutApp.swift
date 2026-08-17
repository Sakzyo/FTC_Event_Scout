import AppKit
import SwiftUI

@main
struct FTCEventScoutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("FTC Event Scout", id: "main") {
            ContentView(model: model)
        }
        .defaultSize(width: 1_180, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Scout") {
                Button("Focus Event Code", action: model.focusEventCode)
                    .keyboardShortcut("l", modifiers: .command)

                Button("Reload Dashboard", action: model.reloadDashboard)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!model.isReady)

                Divider()

                Button("Restart Local Server", action: model.restartBackend)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
