import SwiftUI

@main
struct FTCEventScoutApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .defaultSize(width: 1_180, height: 760)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
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
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
