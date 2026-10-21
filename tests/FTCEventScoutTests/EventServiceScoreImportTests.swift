import Foundation
import XCTest
@testable import FTCEventScout

final class EventServiceScoreImportTests: XCTestCase {
    func testOfficialBioBuzzQualificationSurvivesPythonCSVAndSwiftImport() throws {
        let match = try importFixture("biobuzz_qualification.json")

        XCTAssertEqual(match.redScore.autoScore, 16)
        XCTAssertEqual(match.redScore.teleopScore, 51)
        XCTAssertEqual(match.redScore.endgameScore, 10)
        XCTAssertEqual(match.redScore.foulScore, 20)
        XCTAssertEqual(match.redScore.finalScore, 87)
        XCTAssertEqual(match.blueScore.autoScore, 11)
        XCTAssertEqual(match.blueScore.teleopScore, 45)
        XCTAssertEqual(match.blueScore.endgameScore, 10)
        XCTAssertEqual(match.blueScore.foulScore, 100)
        XCTAssertEqual(match.blueScore.finalScore, 156)

        let rows = BreakdownRow.rows(for: match)
        XCTAssertEqual(rows.first { $0.id == "teleop-flower-red" }?.redValue,
                       "Pollen / Pollen / Pollen / Red Nectar")
        XCTAssertEqual(rows.first { $0.id == "teleop-flower-audience" }?.blueValue, "Empty")
        XCTAssertEqual(rows.first { $0.id == "teleop-garden-pollen-nectar" }?.redValue, "0")
        XCTAssertEqual(rows.first { $0.id == "penalty-major" }?.redValue, "1")
        XCTAssertEqual(rows.first { $0.id == "penalty-major" }?.blueValue, "5")
        XCTAssertEqual(rows.first { $0.id == "rp-swarm" }?.redValue, "Yes")
        XCTAssertEqual(rows.first { $0.id == "rp-pollinator-1" }?.blueValue, "No")
        XCTAssertEqual(rows.filter { $0.id == "total-auto" }.count, 1)
        XCTAssertEqual(rows.filter { $0.id == "total-teleop" }.count, 1)
        XCTAssertEqual(match.redScore.details.map(\.id), match.blueScore.details.map(\.id))
    }

    func testOfficialBioBuzzPlayoffPreservesFlowerOrderAndPenaltyDirection() throws {
        let match = try importFixture("biobuzz_playoff.json")

        XCTAssertEqual(match.series, 5)
        XCTAssertEqual(match.matchNumber, 1)
        XCTAssertEqual(match.redScore.autoScore, 36)
        XCTAssertEqual(match.redScore.teleopScore, 91)
        XCTAssertEqual(match.redScore.endgameScore, 10)
        XCTAssertEqual(match.redScore.foulScore, 0)
        XCTAssertEqual(match.redScore.finalScore, 127)
        XCTAssertEqual(match.blueScore.autoScore, 16)
        XCTAssertEqual(match.blueScore.teleopScore, 38)
        XCTAssertEqual(match.blueScore.endgameScore, 10)
        XCTAssertEqual(match.blueScore.foulScore, 40)
        XCTAssertEqual(match.blueScore.finalScore, 94)
        let flower = match.redScore.details.first { $0.id == "teleop-flower-audience" }
        XCTAssertEqual(flower?.value, "Red Nectar / Pollen / Pollen / Pollen")
    }

    func testMalformedBioBuzzDetailsKeepKnownTotalsAndCallParkingParkPoints() throws {
        let match = try importFixture("biobuzz_qualification.json", malformedDetails: true)

        XCTAssertEqual(match.redScore.autoScore, 16)
        XCTAssertEqual(match.redScore.teleopScore, 51)
        XCTAssertEqual(match.redScore.finalScore, 87)
        XCTAssertEqual(match.redScore.details.first { $0.label == "Park Points" }?.value, "10")
        XCTAssertFalse(match.redScore.details.contains { $0.label == "End Game" })
    }

    private func importFixture(
        _ name: String,
        malformedDetails: Bool = false
    ) throws -> MatchRecord {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repository.appendingPathComponent("tests/fixtures/\(name)")
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
