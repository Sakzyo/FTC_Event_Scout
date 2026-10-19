import SwiftUI

@main
struct FTCEventScoutApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var delegate

    private var model: AppModel { delegate.model }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .defaultSize(width: 1_180, height: 760)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: delegate.updater.checkForUpdates)
                    .disabled(!delegate.updater.canCheckForUpdates)
            }

            SidebarCommands()

            CommandMenu("Scout") {
                Button("Load Event…", action: model.focusEventCode)
                    .keyboardShortcut("l", modifiers: .command)

                Button("Refresh Event", action: model.refreshEvent)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!model.isReady || model.eventCode.isEmpty)

                Divider()

                Button("Restart Data Service", action: model.restartBackend)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(model: model, updater: delegate.updater)
        }
        .windowResizability(.contentSize)
    }
}
