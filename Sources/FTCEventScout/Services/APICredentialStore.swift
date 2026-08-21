import Foundation

struct APICredentialStore {
    static let tokenFileName = ".first-api-token"

    private let fileManager: FileManager
    private let directoryProvider: () throws -> URL

    init(
        fileManager: FileManager = .default,
        directoryProvider: @escaping () throws -> URL = ApplicationDirectories.applicationSupportDirectory
    ) {
        self.fileManager = fileManager
        self.directoryProvider = directoryProvider
    }

    func loadToken() throws -> String? {
        let url = try tokenFileURL()
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let token = String(data: data, encoding: .utf8) else {
            throw APICredentialStoreError.invalidEncoding
        }
        return token
    }

    func saveToken(_ token: String) throws {
        let directory = try directoryProvider()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        let destination = directory.appendingPathComponent(Self.tokenFileName)
        let temporary = directory.appendingPathComponent(".\(Self.tokenFileName).\(UUID().uuidString).tmp")
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]

        guard fileManager.createFile(
            atPath: temporary.path,
            contents: Data(token.utf8),
            attributes: attributes
        ) else {
            throw APICredentialStoreError.couldNotCreateFile
        }

        defer {
            if fileManager.fileExists(atPath: temporary.path) {
                try? fileManager.removeItem(at: temporary)
            }
        }

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        try fileManager.setAttributes(attributes, ofItemAtPath: destination.path)
    }

    private func tokenFileURL() throws -> URL {
        try directoryProvider().appendingPathComponent(Self.tokenFileName)
    }
}

private enum APICredentialStoreError: LocalizedError {
    case couldNotCreateFile
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .couldNotCreateFile:
            "FTC Event Scout could not create its private API credential file."
        case .invalidEncoding:
            "The saved FIRST API token could not be read."
        }
    }
}
