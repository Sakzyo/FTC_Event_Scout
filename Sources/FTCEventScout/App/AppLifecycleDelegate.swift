import AppKit

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = AppUpdateController()
    private var terminationTask: Task<Void, Never>?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        // Sparkle's relaunch and install-on-quit both pass through normal app termination.
        terminationTask = Task {
            do {
                try await model.prepareForUpdate()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                terminationTask = nil
                NSAlert(error: error).runModal()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
