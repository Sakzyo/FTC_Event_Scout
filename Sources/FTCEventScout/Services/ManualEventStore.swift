import Foundation

/// Saves each manual event as its own JSON file in Application Support. It lives outside
/// the cache folder, so clearing cached event data never removes scouts' typed matches.
struct ManualEventStore {
    private let directoryOverride: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        directoryOverride = directory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// Every readable event, most recently edited first. Unreadable files are skipped
    /// and reported so one damaged file cannot hide the rest.
    func loadAll() throws -> (events: [ManualEvent], failures: [String]) {
        let directory = try storageDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        var events: [ManualEvent] = []
        var failures: [String] = []
        for file in files {
            do {
                events.append(try decoder.decode(ManualEvent.self, from: Data(contentsOf: file)))
            } catch {
                failures.append(file.lastPathComponent)
            }
        }
        events.sort { $0.updatedAt > $1.updatedAt }
        return (events, failures)
    }

    func save(_ event: ManualEvent) throws {
        let data = try encoder.encode(event)
        try data.write(to: fileURL(for: event.id), options: .atomic)
    }

    func delete(id: UUID) throws {
        let url = try fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for id: UUID) throws -> URL {
        try storageDirectory().appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func storageDirectory() throws -> URL {
        let directory = try directoryOverride
            ?? ApplicationDirectories.applicationSupportDirectory()
                .appendingPathComponent("manual-events", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
