import Foundation

struct TagStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        decoder = JSONDecoder()
    }

    func load() throws -> [StoredTeamTags] {
        let url = try storageURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try decoder.decode([StoredTeamTags].self, from: Data(contentsOf: url))
    }

    func save(_ groups: [StoredTeamTags]) throws {
        let data = try encoder.encode(groups)
        try data.write(to: storageURL(), options: .atomic)
    }

    private func storageURL() throws -> URL {
        try ApplicationDirectories.applicationSupportDirectory()
            .appendingPathComponent("team-tags.json", isDirectory: false)
    }
}
