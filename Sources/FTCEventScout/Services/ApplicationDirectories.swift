import Foundation

enum ApplicationDirectories {
    private static let directoryName = "FTC Event Scout"

    static func applicationSupportDirectory() throws -> URL {
        try directory(for: .applicationSupportDirectory)
    }

    static func cacheDirectory() throws -> URL {
        try directory(for: .cachesDirectory)
    }

    static func clearCache() throws {
        let fileManager = FileManager.default
        let directory = try cacheDirectory()
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for item in contents {
            try fileManager.removeItem(at: item)
        }
    }

    private static func directory(for searchPath: FileManager.SearchPathDirectory) throws -> URL {
        guard let base = FileManager.default.urls(for: searchPath, in: .userDomainMask).first else {
            throw ApplicationDirectoryError.unavailable(searchPath)
        }
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

enum ApplicationDirectoryError: LocalizedError {
    case unavailable(FileManager.SearchPathDirectory)

    var errorDescription: String? {
        "FTC Event Scout could not open its private data folder."
    }
}
