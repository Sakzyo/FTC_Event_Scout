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

    func testBiobuzzTotalsPrecedePenaltiesAndFinalWithRankingPointsAfterFinal() {
        let details = [
            detail("auto", "Auto", "20", emphasized: true),
            detail("auto-leave", "Leave", "Yes · No"),
            detail("auto-hive-tips", "Hive Tips", "2"),
            detail("auto-hive-points", "Hive Points", "20"),
            detail("total-auto", "Total Auto Points", "999"),
            detail("teleop", "Teleop", "57", emphasized: true),
            detail("teleop-park", "Park", "No · Yes"),
            detail("teleop-flower-red", "Red Flower", "Red Nectar / Blue Nectar / Pollen"),
            detail("teleop-flower-scoring", "Scoring Flower", "Pollen / Red Nectar / Blue Nectar"),
            detail("teleop-flower-blue", "Blue Flower", "Empty"),
            detail("teleop-flower-audience", "Audience Flower", "—"),
            detail("total-teleop", "Total Teleop Points", "999"),
            detail("penalty", "Penalty Points Awarded", "5", emphasized: true),
            detail("final", "Final Score", "82", emphasized: true),
            detail("rp-leave", "Leave RP", "Yes"),
            detail("rp-swarm", "Swarm RP", "No"),
        ]
        let match = MatchRecord(
            id: "qualification-biobuzz",
            series: 0,
            matchNumber: 1,
            redTeams: [1, 2],
            blueTeams: [3, 4],
            redScore: score(auto: 20, teleop: 57, final: 82, details: details),
            blueScore: score(auto: 20, teleop: 57, final: 82, details: details)
        )

        let rows = BreakdownRow.rows(for: match)

        XCTAssertEqual(rows.map(\.id), [
            "auto", "auto-leave", "auto-hive-tips", "auto-hive-points", "total-auto",
            "teleop", "teleop-park", "teleop-flower-red", "teleop-flower-scoring",
            "teleop-flower-blue", "teleop-flower-audience", "total-teleop",
            "penalty", "final", "rp-leave", "rp-swarm",
        ])
        XCTAssertEqual(rows.first { $0.id == "total-auto" }?.redValue, "20")
        XCTAssertEqual(rows.first { $0.id == "total-auto" }?.blueValue, "20")
        XCTAssertEqual(rows.first { $0.id == "total-teleop" }?.redValue, "57")
        XCTAssertEqual(rows.first { $0.id == "total-teleop" }?.blueValue, "57")
        XCTAssertEqual(rows.first { $0.id == "final" }?.redValue, "82")
        XCTAssertEqual(rows.first { $0.id == "final" }?.blueValue, "82")
        XCTAssertEqual(rows.first { $0.id == "rp-leave" }?.redValue, "Yes")
        XCTAssertEqual(rows.first { $0.id == "rp-swarm" }?.redValue, "No")
    }

    func testBiobuzzFlowersKeepFullContentsWithoutDecodeTransforms() throws {
        let values = [
            "Red Nectar / Blue Nectar / Pollen / Red Nectar / Blue Nectar / Pollen",
            "Pollen / Red Nectar / Blue Nectar",
            "Empty",
            "—",
        ]
        let details = zip(
            ["teleop-flower-red", "teleop-flower-scoring", "teleop-flower-blue", "teleop-flower-audience"],
            values
        ).map { detail($0.0, "Flower", $0.1) }
        let match = MatchRecord(
            id: "qualification-biobuzz-flowers",
            series: 0,
            matchNumber: 1,
            redTeams: [1, 2],
            blueTeams: [3, 4],
            redScore: score(auto: 0, teleop: 0, final: 0, details: details),
            blueScore: score(auto: 0, teleop: 0, final: 0, details: details)
        )

        let flowers = BreakdownRow.rows(for: match).filter { $0.id.hasPrefix("teleop-flower-") }

        XCTAssertEqual(flowers.map(\.redValue), values)
        XCTAssertEqual(flowers.map(\.blueValue), values)
        for row in flowers {
            let value = try XCTUnwrap(row.redValue)
            XCTAssertFalse(row.usesDecodePatternColors)
            XCTAssertEqual(
                ScoreBreakdownTextStyler.segments(
                    in: value,
                    usesDecodePatternColors: row.usesDecodePatternColors
                ),
                [ScoreBreakdownTextSegment(text: value, role: .standard)]
            )
        }
    }

    func testOnlyBiobuzzFlowerContentsCanWrapOntoMultipleLines() {
        for id in [
            "teleop-flower-red", "teleop-flower-scoring",
            "teleop-flower-blue", "teleop-flower-audience",
        ] {
            let row = BreakdownRow(
                id: id,
                label: "Flower",
                redValue: "Red Nectar / Blue Nectar / Pollen / Red Nectar / Blue Nectar / Pollen",
                blueValue: "Pollen",
                indent: 1,
                emphasized: false
            )
            XCTAssertNil(row.valueLineLimit, id)
        }
        for id in ["auto-hive-tips", "auto-leave", "teleop-park", "teleop-flower-points", "auto-classifier", "teleop-classifier", "final"] {
            let row = BreakdownRow(
                id: id,
                label: "Value",
                redValue: "1",
                blueValue: "2",
                indent: 1,
                emphasized: false
            )
            XCTAssertEqual(row.valueLineLimit, 1, id)
        }
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

    func testLeadingAllianceComparesOnlySingleNumericValues() {
        func leader(_ red: String?, _ blue: String?) -> AllianceColor? {
            BreakdownRow(
                id: "row",
                label: "Row",
                redValue: red,
                blueValue: blue,
                indent: 0,
                emphasized: false
            ).leadingAlliance
        }

        XCTAssertEqual(leader("42", "39"), .red)
        XCTAssertEqual(leader("7.5", " 12 "), .blue)
        XCTAssertNil(leader("18", "18"))
        XCTAssertNil(leader("3 / 2 / 1", "1 / 0 / 0"))
        XCTAssertNil(leader("Full", "Partial"))
        XCTAssertNil(leader("GPP", "PGP"))
        XCTAssertNil(leader("Red Nectar / Blue Nectar / Pollen", "Pollen / Red Nectar"))
        XCTAssertNil(leader("Yes · No", "Yes · Yes"))
        XCTAssertNil(leader("Empty", "—"))
        XCTAssertNil(leader("12", nil))
        XCTAssertNil(leader("nan", "4"))
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
