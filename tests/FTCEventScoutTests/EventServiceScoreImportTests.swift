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
        try BiobuzzFixture.importThroughPython(name, malformedDetails: malformedDetails)
    }
}
