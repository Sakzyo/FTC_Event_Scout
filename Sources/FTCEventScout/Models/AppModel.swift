import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum LaunchState: Equatable {
        case idle
        case credentialsRequired
        case starting
        case ready(URL)
        case pythonRequired
        case pythonPackagesRequired(String)
        case failed(String)
    }

    var launchState: LaunchState = .idle
    var username: String
    var token: String
    var settingsMessage: String?
    private(set) var reloadToken = 0
    private(set) var focusToken = 0

    private let backendService = BackendService()

    init() {
        username = (try? KeychainStore.value(for: .username)) ?? ""
        token = (try? KeychainStore.value(for: .token)) ?? ""
    }

    var isReady: Bool {
        if case .ready = launchState {
            return true
        }
        return false
    }

    var hasCompleteCredentials: Bool {
        !normalizedUsername.isEmpty && !normalizedToken.isEmpty
    }

    func startIfNeeded() {
        guard launchState == .idle else { return }
        startBackend()
    }

    func restartBackend() {
        startBackend()
    }

    func reloadDashboard() {
        guard isReady else { return }
        reloadToken += 1
    }

    func focusEventCode() {
        guard isReady else { return }
        focusToken += 1
    }

    func saveSettings() {
        saveCredentialsAndStart()
    }

    func saveCredentialsAndStart() {
        guard hasCompleteCredentials else {
            settingsMessage = "Enter both your FIRST API username and token."
            launchState = .credentialsRequired
            return
        }

        do {
            username = normalizedUsername
            token = normalizedToken
            try KeychainStore.set(username, for: .username)
            try KeychainStore.set(token, for: .token)
            settingsMessage = "Credentials saved. Starting the local server…"
            startBackend()
        } catch {
            settingsMessage = "Could not save credentials: \(error.localizedDescription)"
            launchState = .credentialsRequired
        }
    }

    private func startBackend() {
        guard hasCompleteCredentials else {
            backendService.stop()
            settingsMessage = nil
            launchState = .credentialsRequired
            return
        }

        launchState = .starting
        backendService.start(
            username: normalizedUsername,
            token: normalizedToken
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                self.launchState = .ready(url)
                self.settingsMessage = "Credentials saved. The local server is ready."
            case .failure(let error):
                if let backendError = error as? BackendServiceError {
                    switch backendError {
                    case .pythonNotFound:
                        self.launchState = .pythonRequired
                    case .missingPythonPackages:
                        self.launchState = .pythonPackagesRequired(error.localizedDescription)
                    default:
                        self.launchState = .failed(error.localizedDescription)
                    }
                } else {
                    self.launchState = .failed(error.localizedDescription)
                }
                self.settingsMessage = error.localizedDescription
            }
        }
    }

    private var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
