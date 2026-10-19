import Combine
import Foundation
import Observation
import Sparkle

struct AppUpdateConfiguration {
    init(bundle: Bundle) throws {
        guard bundle.bundleURL.pathExtension == "app" else {
            throw AppUpdateConfigurationError.notPackagedApplication
        }
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), let host = url.host, !host.isEmpty else {
            throw AppUpdateConfigurationError.insecureFeed
        }
        var secureFeed = url.scheme == "https"
        #if DEBUG
        // Local signed-update verification is available only in debug builds.
        secureFeed = secureFeed || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host))
        #endif
        guard secureFeed else { throw AppUpdateConfigurationError.insecureFeed }
        guard let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            throw AppUpdateConfigurationError.invalidPublicKey
        }
        guard let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty else {
            throw AppUpdateConfigurationError.missingBuildNumber
        }
        guard bundle.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool == true else {
            throw AppUpdateConfigurationError.signatureVerificationRequired
        }
    }
}

enum AppUpdateConfigurationError: LocalizedError, Equatable {
    case notPackagedApplication
    case insecureFeed
    case invalidPublicKey
    case missingBuildNumber
    case signatureVerificationRequired

    var errorDescription: String? {
        switch self {
        case .notPackagedApplication:
            "Software updates are available in the packaged FTC Event Scout app."
        case .insecureFeed:
            "The app does not have a secure update feed configured."
        case .invalidPublicKey:
            "The app does not have a valid update-signing public key."
        case .missingBuildNumber:
            "The app does not have an update build number."
        case .signatureVerificationRequired:
            "Updates must be signature-verified before extraction."
        }
    }
}

@MainActor
@Observable
final class AppUpdateController {
    static let releasesPageURL = URL(string: "https://github.com/Sakzyo/FTC_Event_Scout/releases/latest")!

    let currentVersionText: String
    private(set) var canCheckForUpdates = false
    private(set) var unavailableReason: String?

    var automaticallyChecksForUpdates = false {
        didSet {
            guard let updater = controller?.updater,
                  updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    var automaticallyDownloadsUpdates = false {
        didSet {
            guard let updater = controller?.updater,
                  updater.automaticallyDownloadsUpdates != automaticallyDownloadsUpdates else { return }
            updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var subscriptions = Set<AnyCancellable>()

    init() {
        currentVersionText = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development build"
        do {
            _ = try AppUpdateConfiguration(bundle: .main)
            let controller = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            self.controller = controller
            let updater = controller.updater
            updater.publisher(for: \.canCheckForUpdates)
                .sink { [weak self] in self?.canCheckForUpdates = $0 }
                .store(in: &subscriptions)
            updater.publisher(for: \.automaticallyChecksForUpdates)
                .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
                .store(in: &subscriptions)
            updater.publisher(for: \.automaticallyDownloadsUpdates)
                .sink { [weak self] in self?.automaticallyDownloadsUpdates = $0 }
                .store(in: &subscriptions)
            try updater.start()
        } catch {
            unavailableReason = error.localizedDescription
            controller = nil
            subscriptions.removeAll()
            canCheckForUpdates = false
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller?.checkForUpdates(nil)
    }
}
