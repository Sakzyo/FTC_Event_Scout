import Foundation
import XCTest
@testable import FTCEventScout

/// Shared access to the recorded BIOBUZZ payloads in `tests/fixtures`.
enum BiobuzzFixture {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func url(_ name: String) -> URL {
        repository.appendingPathComponent("tests/fixtures/\(name)")
    }

    /// Runs a recorded FIRST Events payload through `scrape.py` and the Swift CSV import.
    static func importThroughPython(
        _ name: String,
        malformedDetails: Bool = false
    ) throws -> MatchRecord {
        let fixture = url(name)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let csvURL = directory.appendingPathComponent("Match Details.csv")

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = repository
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["PYTHONDONTWRITEBYTECODE": "1"], uniquingKeysWith: { _, new in new }
        )
        process.arguments = ["python3", "-c", """
        import csv, json, sys
        from scrape import flatten_match
        fixture = json.load(open(sys.argv[1]))
        score = fixture['score']
        key = (score['matchLevel'], score['matchSeries'], score['matchNumber'])
        lookup = {key: {item['alliance']: item for item in score['alliances']}}
        row = flatten_match(fixture['match'], lookup, 2026)
        if sys.argv[2] == 'malformed':
            row['Red Score Breakdown'] = '{invalid-json'
        writer = csv.DictWriter(sys.stdout, fieldnames=list(row))
        writer.writeheader()
        writer.writerow(row)
        """, fixture.path, malformedDetails ? "malformed" : "valid"]
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let csv = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: errorData, as: UTF8.self))
        try csv.write(to: csvURL)

        let matches = try EventService().parseMatches(at: csvURL, season: 2026)
        return try XCTUnwrap(matches.first)
    }
}
