import XCTest
@testable import FTCEventScout

final class ScoreBreakdownRowTests: XCTestCase {
    func testTotalsAreInsertedAfterAutoAndTeleopSectionsForBothAlliances() {
        let match = MatchRecord(
            id: "qualification-1",
            series: 0,
            matchNumber: 1,
            redTeams: [1, 2],
            blueTeams: [3, 4],
            redScore: score(
                auto: 18,
                teleop: 42,
                final: 65,
                details: decodeDetails(auto: "18", teleop: "42", penalty: "5", final: "65")
            ),
            blueScore: score(
                auto: 16,
                teleop: 39,
                final: 55,
                details: decodeDetails(auto: "16", teleop: "39", penalty: "0", final: "55")
            )
        )

        let rows = BreakdownRow.rows(for: match)

        XCTAssertEqual(
            rows.map(\.id),
            [
                "auto", "auto-artifact-points", "total-auto",
                "teleop", "teleop-artifact-points", "total-teleop",
                "penalty", "final",
            ]
        )
        XCTAssertEqual(rows.first { $0.id == "total-auto" }?.redValue, "18")
        XCTAssertEqual(rows.first { $0.id == "total-auto" }?.blueValue, "16")
        XCTAssertEqual(rows.first { $0.id == "total-teleop" }?.redValue, "42")
        XCTAssertEqual(rows.first { $0.id == "total-teleop" }?.blueValue, "39")
    }

    func testLegacyTeleopTotalFollowsEndGameAndPrecedesPenalties() {
        let details = [
            detail("auto", "Autonomous", "30", emphasized: true),
            detail("driver", "Driver Controlled", "17", emphasized: true),
            detail("endgame", "End Game", "15", emphasized: true),
            detail("penalty", "Penalty Points Awarded", "5", emphasized: true),
            detail("final", "Final Score", "67", emphasized: true),
        ]
        let match = MatchRecord(
            id: "qualification-2",
            series: 0,
            matchNumber: 2,
            redTeams: [1, 2],
            blueTeams: [3, 4],
            redScore: score(auto: 30, teleop: 32, final: 67, details: details),
            blueScore: score(auto: 20, teleop: 25, final: 45, details: details)
        )

        let rows = BreakdownRow.rows(for: match)

        XCTAssertEqual(
            rows.map(\.id),
            ["auto", "total-auto", "driver", "endgame", "total-teleop", "penalty", "final"]
        )
    }

    func testOnlyRequestedScoreRowsUseBoldValues() {
        let boldIDs = [
            "auto", "total-auto", "teleop", "total-teleop",
            "penalty", "penalty-minor", "final",
        ].filter {
            BreakdownRow(
                id: $0,
                label: $0,
                redValue: "1",
                blueValue: "1",
                indent: 0,
                emphasized: false
            ).usesBoldValue
        }

        XCTAssertEqual(boldIDs, ["total-auto", "total-teleop", "penalty", "final"])
    }

    private func score(
        auto: Double,
        teleop: Double,
        final: Double,
        details: [ScoreBreakdownDetail]
    ) -> ScoreBreakdown {
        ScoreBreakdown(
            autoScore: auto,
            teleopScore: teleop,
            endgameScore: nil,
            foulScore: nil,
            foulCommitted: nil,
            majorFouls: nil,
            minorFouls: nil,
            finalScore: final,
            details: details
        )
    }

    private func decodeDetails(
        auto: String,
        teleop: String,
        penalty: String,
        final: String
    ) -> [ScoreBreakdownDetail] {
        [
            detail("auto", "Auto", auto, emphasized: true),
            detail("auto-artifact-points", "Artifact Points", "10"),
            detail("teleop", "Teleop", teleop, emphasized: true),
            detail("teleop-artifact-points", "Artifact Points", "30"),
            detail("penalty", "Penalty Points Awarded", penalty, emphasized: true),
            detail("final", "Final Score", final, emphasized: true),
        ]
    }

    private func detail(
        _ id: String,
        _ label: String,
        _ value: String,
        emphasized: Bool = false
    ) -> ScoreBreakdownDetail {
        ScoreBreakdownDetail(
            id: id,
            label: label,
            value: value,
            indent: emphasized ? 0 : 1,
            emphasized: emphasized
        )
    }
}
