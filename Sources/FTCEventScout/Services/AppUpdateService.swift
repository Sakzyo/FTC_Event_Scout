import AppKit
import CryptoKit
import Foundation
import Observation

struct AppVersion: Comparable, CustomStringConvertible, Equatable, Sendable {
    private enum PrereleaseIdentifier: Equatable, Sendable {
        case number(Int)
        case text(String)
    }

    private let components: [Int]
    private let prerelease: [PrereleaseIdentifier]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }

        let withoutBuildMetadata = value.split(separator: "+", maxSplits: 1).first.map(String.init) ?? value
        let pieces = withoutBuildMetadata.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numericPieces = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard !numericPieces.isEmpty,
              numericPieces.allSatisfy({ !$0.isEmpty && Int($0) != nil }) else {
            return nil
        }

        components = numericPieces.compactMap { Int($0) }
        if pieces.count == 2, !pieces[1].isEmpty {
            prerelease = pieces[1].split(separator: ".").map { identifier in
                if let number = Int(identifier) {
                    return .number(number)
                }
                return .text(identifier.lowercased())
            }
        } else {
            prerelease = []
        }
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let componentCount = max(lhs.components.count, rhs.components.count)
        for index in 0..<componentCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }

        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty
        }

        for index in 0..<max(lhs.prerelease.count, rhs.prerelease.count) {
            guard index < lhs.prerelease.count else { return true }
            guard index < rhs.prerelease.count else { return false }

            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right { continue }

            switch (left, right) {
            case let (.number(leftNumber), .number(rightNumber)):
                return leftNumber < rightNumber
            case (.number, .text):
                return true
            case (.text, .number):
                return false
            case let (.text(leftText), .text(rightText)):
                return leftText < rightText
            }
        }

        return false
    }
}

struct AppRelease: Equatable, Sendable {
    let version: AppVersion
    let tagName: String
    let releasePageURL: URL
    let installer: ReleaseAsset
    let checksum: ReleaseAsset?
}

struct ReleaseAsset: Equatable, Sendable {
    let name: String
    let downloadURL: URL
    let digest: String?
}

struct AppUpdateService {
    static let releasesPageURL = URL(
        string: "https://github.com/Sakzyo/FTC_Event_Scout/releases/latest"
    )!

    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/Sakzyo/FTC_Event_Scout/releases/latest"
    )!

    private let session: URLSession
    private let fileManager: FileManager
    private let bundle: Bundle

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) {
        self.session = session
        self.fileManager = fileManager
        self.bundle = bundle
    }

    var currentVersionText: String {
        guard let value = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !value.isEmpty else {
            return "Development build"
        }
        return value
    }

    func fetchLatestRelease() async throws -> AppRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("FTC-Event-Scout-Updater", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try Self.decodeRelease(data)
    }

    func isNewerThanInstalled(_ release: AppRelease) -> Bool {
        guard let installedVersion = AppVersion(currentVersionText) else {
            return true
        }
        return release.version > installedVersion
    }

    func downloadInstaller(for release: AppRelease) async throws -> URL {
        let expectedDigest = try await expectedSHA256(for: release)
        let directory = try ApplicationDirectories.cacheDirectory()
            .appendingPathComponent("Updates", isDirectory: true)
            .appendingPathComponent(release.tagName, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(release.installer.name)

        if fileManager.fileExists(atPath: destination.path),
           try Self.sha256(of: destination) == expectedDigest {
            return destination
        }

        let (temporaryURL, response) = try await session.download(from: release.installer.downloadURL)
        do {
            try Self.validate(response)
            guard response.url?.scheme?.lowercased() == "https" else {
                throw AppUpdateError.insecureDownload
            }

            let actualDigest = try Self.sha256(of: temporaryURL)
            guard actualDigest == expectedDigest else {
                throw AppUpdateError.checksumMismatch
            }

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func decodeRelease(_ data: Data) throws -> AppRelease {
        let response: GitHubReleaseResponse
        do {
            response = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
        } catch {
            throw AppUpdateError.invalidReleaseResponse
        }

        guard let version = AppVersion(response.tagName),
              response.htmlURL.scheme?.lowercased() == "https" else {
            throw AppUpdateError.invalidReleaseResponse
        }

        let installerResponse = response.assets.first { asset in
            let name = asset.name.lowercased()
            return name.hasPrefix("ftc-event-scout-") && name.hasSuffix(".dmg")
        }
        guard let installerResponse,
              installerResponse.name == URL(fileURLWithPath: installerResponse.name).lastPathComponent,
              installerResponse.browserDownloadURL.scheme?.lowercased() == "https",
              installerResponse.browserDownloadURL.host?.lowercased() == "github.com" else {
            throw AppUpdateError.installerUnavailable
        }

        let installer = ReleaseAsset(
            name: installerResponse.name,
            downloadURL: installerResponse.browserDownloadURL,
            digest: installerResponse.digest
        )
        let checksumResponse = response.assets.first {
            $0.name == "\(installer.name).sha256"
        }
        let checksum = checksumResponse.flatMap { asset -> ReleaseAsset? in
            guard asset.browserDownloadURL.scheme?.lowercased() == "https",
                  asset.browserDownloadURL.host?.lowercased() == "github.com" else {
                return nil
            }
            return ReleaseAsset(
                name: asset.name,
                downloadURL: asset.browserDownloadURL,
                digest: asset.digest
            )
        }

        return AppRelease(
            version: version,
            tagName: response.tagName,
            releasePageURL: response.htmlURL,
            installer: installer,
            checksum: checksum
        )
    }

    static func normalizedSHA256(_ value: String) -> String? {
        let candidate = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "sha256:", with: "")
        guard candidate.count == 64,
              candidate.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return candidate
    }

    static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func expectedSHA256(for release: AppRelease) async throws -> String {
        if let digest = release.installer.digest,
           let normalized = Self.normalizedSHA256(digest) {
            return normalized
        }

        guard let checksum = release.checksum else {
            throw AppUpdateError.checksumUnavailable
        }
        let (data, response) = try await session.data(from: checksum.downloadURL)
        try Self.validate(response)
        guard let text = String(data: data, encoding: .utf8),
              let firstField = text.split(whereSeparator: { $0.isWhitespace }).first,
              let digest = Self.normalizedSHA256(String(firstField)) else {
            throw AppUpdateError.invalidChecksum
        }
        return digest
    }

    private static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidServerResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AppUpdateError.serverError(response.statusCode)
        }
    }
}

@MainActor
@Observable
final class AppUpdateController {
    enum State: Equatable {
        case idle
        case checking
        case downloading
        case upToDate
        case installerOpened
        case failed
    }

    private let service: AppUpdateService
    private(set) var state: State = .idle
    private(set) var latestRelease: AppRelease?
    private(set) var statusMessage = "Check for a newer published version of FTC Event Scout."
    private var downloadedInstallerURL: URL?

    init(service: AppUpdateService = AppUpdateService()) {
        self.service = service
    }

    var currentVersionText: String {
        service.currentVersionText
    }

    var isWorking: Bool {
        state == .checking || state == .downloading
    }

    var buttonTitle: String {
        switch state {
        case .idle:
            return "Check for Updates"
        case .checking:
            return "Checking…"
        case .downloading:
            return "Downloading…"
        case .upToDate:
            return "Check Again"
        case .installerOpened:
            return "Open Installer Again"
        case .failed:
            return "Try Again"
        }
    }

    func performUpdate() async {
        if state == .installerOpened, let downloadedInstallerURL {
            openInstaller(at: downloadedInstallerURL)
            return
        }

        state = .checking
        statusMessage = "Checking GitHub for the latest release…"

        do {
            let release = try await service.fetchLatestRelease()
            latestRelease = release
            guard service.isNewerThanInstalled(release) else {
                state = .upToDate
                statusMessage = "FTC Event Scout is up to date."
                return
            }

            state = .downloading
            statusMessage = "Downloading and verifying FTC Event Scout \(release.version)…"
            let installerURL = try await service.downloadInstaller(for: release)
            downloadedInstallerURL = installerURL
            openInstaller(at: installerURL)
        } catch {
            state = .failed
            statusMessage = error.localizedDescription
        }
    }

    private func openInstaller(at url: URL) {
        guard NSWorkspace.shared.open(url) else {
            state = .failed
            statusMessage = AppUpdateError.couldNotOpenInstaller.localizedDescription
            return
        }

        state = .installerOpened
        if let release = latestRelease {
            statusMessage = "The verified FTC Event Scout \(release.version) installer is open. Drag the app to Applications and replace the existing copy."
        } else {
            statusMessage = "The verified installer is open. Drag the app to Applications and replace the existing copy."
        }
    }
}

enum AppUpdateError: LocalizedError {
    case invalidReleaseResponse
    case invalidServerResponse
    case serverError(Int)
    case installerUnavailable
    case insecureDownload
    case checksumUnavailable
    case invalidChecksum
    case checksumMismatch
    case couldNotOpenInstaller

    var errorDescription: String? {
        switch self {
        case .invalidReleaseResponse:
            return "The latest release information could not be read."
        case .invalidServerResponse:
            return "GitHub returned an invalid response."
        case let .serverError(statusCode):
            return "GitHub could not check for updates (HTTP \(statusCode))."
        case .installerUnavailable:
            return "The latest release does not include a compatible FTC Event Scout installer."
        case .insecureDownload:
            return "The update download was not delivered over a secure connection."
        case .checksumUnavailable:
            return "The update could not be verified because its SHA-256 checksum is unavailable."
        case .invalidChecksum:
            return "The update's SHA-256 checksum is invalid."
        case .checksumMismatch:
            return "The downloaded update did not match its published SHA-256 checksum and was discarded."
        case .couldNotOpenInstaller:
            return "The verified update was downloaded, but macOS could not open the installer."
        }
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubReleaseAssetResponse]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAssetResponse: Decodable {
    let name: String
    let browserDownloadURL: URL
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}
