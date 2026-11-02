import Foundation
import XCTest
@testable import FTCEventScout

final class ManualEventTests: XCTestCase {
    // MARK: BIOBUZZ scoring

    func testBiobuzzScoringReproducesOfficialFixtures() throws {
        for name in ["biobuzz_qualification.json", "biobuzz_playoff.json"] {
            let fixture = try FixtureMatch(name)
            for alliance in [AllianceColor.red, .blue] {
                let official = fixture.alliance(alliance)
                let opponent = fixture.alliance(alliance == .red ? .blue : .red)
                let result = BiobuzzScoring.score(
                    fixture.match.input(for: alliance).biobuzz,
                    alliance: alliance,
                    flowers: fixture.match.flowers
                )
                let context = "\(name) \(alliance)"
                XCTAssertEqual(result.autoLeavePoints, official.int("autoLeavePoints"), context)
                XCTAssertEqual(result.autoParkPoints, official.int("autoParkPoints"), context)
                XCTAssertEqual(result.autoHivePoints, official.int("autoHivePoints"), context)
                XCTAssertEqual(result.teleopHivePoints, official.int("teleopHivePoints"), context)
                XCTAssertEqual(result.teleopFlowerPoints, official.int("teleopFlowerPoints"), context)
                XCTAssertEqual(result.teleopGardenPoints, official.int("teleopGardenPoints"), context)
                XCTAssertEqual(result.teleopParkPoints, official.int("teleopParkPoints"), context)
                XCTAssertEqual(result.autoPoints, official.int("autoPoints"), context)
                XCTAssertEqual(result.teleopPoints, official.int("teleopPoints"), context)
                XCTAssertEqual(result.foulPointsCommitted, official.int("foulPointsCommitted"), context)
                XCTAssertEqual(result.preFoulTotal, official.int("preFoulTotal"), context)
                XCTAssertEqual(result.preFoulTotal + opponent.int("foulPointsCommitted"), official.int("totalPoints"), context)
                XCTAssertEqual(result.swarmRP, official.bool("swarmRP"), context)
                XCTAssertEqual(result.pollinator1RP, official.bool("pollinator1RP"), context)
                XCTAssertEqual(result.pollinator2RP, official.bool("pollinator2RP"), context)
            }
        }
    }

    func testManualBreakdownMatchesFirstEventsImport() throws {
        for name in ["biobuzz_qualification.json", "biobuzz_playoff.json"] {
            let fixture = try FixtureMatch(name)
            let imported = try BiobuzzFixture.importThroughPython(name)
            let event = ManualEvent(name: "Fixture", season: 2026, matches: [fixture.match])
            let manual = try XCTUnwrap(ManualEventBuilder.matchRecords(for: event).first)

            XCTAssertEqual(manual.series, imported.series, name)
            XCTAssertEqual(manual.matchNumber, imported.matchNumber, name)
            // Teams are not compared: the recorded payloads mark every team `onField: false`,
            // which `scrape.py` drops.
            for (mine, theirs) in [(manual.redScore, imported.redScore), (manual.blueScore, imported.blueScore)] {
                XCTAssertEqual(mine.autoScore, theirs.autoScore, name)
                XCTAssertEqual(mine.teleopScore, theirs.teleopScore, name)
                XCTAssertEqual(mine.endgameScore, theirs.endgameScore, name)
                XCTAssertEqual(mine.foulScore, theirs.foulScore, name)
                XCTAssertEqual(mine.finalScore, theirs.finalScore, name)
                XCTAssertEqual(mine.details, theirs.details, name)
            }
            XCTAssertEqual(manual.nonPenaltyScore(for: .red), imported.nonPenaltyScore(for: .red), name)
        }
    }

    func testOverridesReplaceCalculatedPointsAndFlowTotals() {
        var input = BiobuzzAllianceInput()
        input.autoRobot1Leave = true
        input.teleopHivePollenNectar = 4
        input.setOverride(13, for: .teleopFlower)

        let result = BiobuzzScoring.score(input, alliance: .red, flowers: BiobuzzFlowers())
        XCTAssertEqual(result.autoLeavePoints, 3)
        XCTAssertEqual(result.teleopFlowerPoints, 13)
        XCTAssertEqual(result.teleopPoints, 8 + 13)
        XCTAssertEqual(BiobuzzScoring.calculatedScore(input, alliance: .red, flowers: BiobuzzFlowers()).teleopFlowerPoints, 0)
    }

    func testTopNectarOwnsFlowerAndEachAllianceGetsBottomNectarBonus() {
        var flowers = BiobuzzFlowers()
        flowers.scoring = [.redNectar, .pollen, .blueNectar]

        XCTAssertEqual(BiobuzzScoring.flowerPoints(for: .blue, flowers: flowers), 3 * 2 + 5)
        XCTAssertEqual(BiobuzzScoring.flowerPoints(for: .red, flowers: flowers), 5)
    }

    // MARK: Event building

    func testStandingsMatchPythonOPRForSeedEvent() throws {
        let matchesURL = BiobuzzFixture.repository.appendingPathComponent("event_results/USIACMP Match Details.csv")
        let oprURL = BiobuzzFixture.repository.appendingPathComponent("events_teams_opr/USIACMP OPR.csv")
        let matches = try EventService().parseMatches(at: matchesURL, season: 2025)
        let standings = ManualEventBuilder.standings(from: matches)
        let expected = try CSVParser.rows(from: Data(contentsOf: oprURL))

        XCTAssertEqual(standings.count, expected.count)
        let byTeam = Dictionary(uniqueKeysWithValues: standings.map { ($0.teamNumber, $0) })
        for row in expected {
            let team = try XCTUnwrap(Int(row["Team Number"] ?? ""))
            let standing = try XCTUnwrap(byTeam[team], "Team \(team)")
            let pairs: [(Double?, String)] = [
                (standing.totalOPR, "OPR"),
                (standing.nonPenaltyOPR, "npOPR"),
                (standing.autoOPR, "Auto OPR"),
                (standing.teleopOPR, "Teleop OPR"),
                (standing.endgameOPR, "Endgame OPR"),
            ]
            for (value, column) in pairs {
                let python = try XCTUnwrap(Double(row[column] ?? ""), "\(team) \(column)")
                XCTAssertEqual(try XCTUnwrap(value), python, accuracy: 1e-3, "\(team) \(column)")
            }
        }
    }

    func testScheduledMatchesFeedPredictionsAndRankings() {
        var matches = (1 ... 6).map { number in
            totalsMatch(number, red: (number, number + 10), blue: (number + 20, number + 30), red: 50 + number, blue: 40)
        }
        matches.append(ManualMatch(number: 7, red1: 1, red2: 2, blue1: 99, blue2: 21))
        let event = ManualEvent(name: "Scrimmage", season: 2024, matches: matches)

        let data = ManualEventBuilder.eventData(for: event)
        XCTAssertEqual(data.mode, .manual)
        XCTAssertEqual(data.eventCode, event.eventCode)
        XCTAssertEqual(data.matches.count, 7)
        XCTAssertEqual(data.oprcAnalysis.predictions.count, 1)
        XCTAssertTrue(data.standings.contains { $0.teamNumber == 99 && $0.totalOPR == nil })
        XCTAssertEqual(data.teamRecords[1]?.wins, 1)
    }

    func testTotalsFinalIsSumUnlessOverridden() {
        var match = totalsMatch(1, red: (1, 2), blue: (3, 4), red: 0, blue: 0)
        match.red.totals = ManualTotals(auto: 20, driverControlled: 30, endgame: 10, penaltyReceived: 5)
        var breakdown = ManualEventBuilder.scoreBreakdowns(for: match, season: 2024).red
        XCTAssertEqual(breakdown.finalScore, 65)
        XCTAssertEqual(breakdown.teleopScore, 40)
        XCTAssertEqual(breakdown.details.map(\.id), ["auto", "teleop", "endgame", "penalty", "final"])

        match.red.totals.finalOverride = 70
        breakdown = ManualEventBuilder.scoreBreakdowns(for: match, season: 2024).red
        XCTAssertEqual(breakdown.finalScore, 70)
    }

    // MARK: CSV

    func testCSVRoundTripKeepsEveryField() throws {
        var detailed = try FixtureMatch("biobuzz_qualification.json").match
        detailed.red.biobuzz.setOverride(9, for: .teleopGarden)
        var totals = totalsMatch(2, red: (5, 6), blue: (7, 8), red: 70, blue: 60)
        totals.level = .playoff
        totals.game = 2
        totals.red.totals.finalOverride = 75
        let scheduled = ManualMatch(number: 3, red1: 1, red2: 2, blue1: 3, blue2: 4, entryStyle: .detailed)
        let event = ManualEvent(name: "Round, \"Trip\"", season: 2026, matches: [detailed, totals, scheduled])

        let csv = ManualEventCSV.export(event)
        let result = try ManualEventCSV.importMatches(from: Data(csv.utf8), season: 2026)

        XCTAssertEqual(result.issues, [])
        XCTAssertFalse(result.usedMatchDetailsFormat)
        XCTAssertEqual(result.matches.map(withoutID), event.sortedMatches.map(withoutID))
    }

    func testMatchDetailsCSVImportsAsTotalsWithSameScores() throws {
        let url = BiobuzzFixture.repository.appendingPathComponent("event_results/USIACMP Match Details.csv")
        let data = try Data(contentsOf: url)
        let result = try ManualEventCSV.importMatches(from: data, season: 2025)
        let original = try EventService().parseMatches(data: data, season: 2025)

        XCTAssertTrue(result.usedMatchDetailsFormat)
        XCTAssertEqual(result.issues, [])
        XCTAssertEqual(result.matches.count, original.count)
        let rebuilt = ManualEventBuilder.matchRecords(for: ManualEvent(name: "Seed", season: 2025, matches: result.matches))
        for (mine, theirs) in zip(rebuilt, original) {
            XCTAssertEqual(mine.redTeams, theirs.redTeams)
            XCTAssertEqual(mine.redScore.finalScore, theirs.redScore.finalScore)
            XCTAssertEqual(mine.blueScore.finalScore, theirs.blueScore.finalScore)
            XCTAssertEqual(mine.nonPenaltyScore(for: .blue), theirs.nonPenaltyScore(for: .blue))
        }
    }

    func testCSVImportReportsBadRowsAndKeepsGoodOnes() throws {
        let csv = """
        Level,Match,Red1,Red2,Blue1,Blue2,Red Auto,Blue Auto
        Q,1,1,2,3,4,10,12
        Q,2,1,2,3,,10,12
        Q,1,5,6,7,8,1,1
        X,4,1,2,3,4,,
        Q,5,1,1,3,4,,
        Q,6,1,2,3,4,ten,
        Q,7,9,10,11,12,,
        """
        let existing = [ManualMatch(number: 7, red1: 1, red2: 2, blue1: 3, blue2: 4)]
        let result = try ManualEventCSV.importMatches(from: Data(csv.utf8), season: 2024, existing: existing)

        XCTAssertEqual(result.matches.map(\.number), [1])
        XCTAssertTrue(result.matches[0].isScored)
        XCTAssertEqual(result.issues.map(\.line), [3, 4, 5, 6, 7, 8])
    }

    // MARK: Storage

    func testStoreSavesListsAndDeletesEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ManualEventStore(directory: directory)
        let first = ManualEvent(name: "First", season: 2026, matches: [try FixtureMatch("biobuzz_playoff.json").match])
        var second = ManualEvent(name: "Second", season: 2024)
        second.updatedAt = first.updatedAt.addingTimeInterval(60)

        try store.save(first)
        try store.save(second)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let loaded = try store.loadAll()
        XCTAssertEqual(loaded.events.map(\.name), ["Second", "First"])
        XCTAssertEqual(loaded.events.last?.matches, first.matches)
        XCTAssertEqual(loaded.failures, ["broken.json"])

        try store.delete(id: first.id)
        XCTAssertEqual(try store.loadAll().events.map(\.name), ["Second"])
    }

    // MARK: Helpers

    private func totalsMatch(
        _ number: Int,
        red redTeams: (Int, Int),
        blue blueTeams: (Int, Int),
        red redScore: Int,
        blue blueScore: Int
    ) -> ManualMatch {
        var match = ManualMatch(
            number: number,
            red1: redTeams.0,
            red2: redTeams.1,
            blue1: blueTeams.0,
            blue2: blueTeams.1,
            isScored: true
        )
        match.red.totals = ManualTotals(auto: redScore / 2, driverControlled: redScore - redScore / 2)
        match.blue.totals = ManualTotals(auto: blueScore / 2, driverControlled: blueScore - blueScore / 2)
        return match
    }

    private func withoutID(_ match: ManualMatch) -> ManualMatch {
        var copy = match
        copy.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        return copy
    }
}

/// A recorded FIRST Events BIOBUZZ match rebuilt as manual input.
private struct FixtureMatch {
    struct Alliance {
        let values: [String: Any]

        func int(_ key: String) -> Int { values[key] as? Int ?? -1 }
        func bool(_ key: String) -> Bool { values[key] as? Bool ?? false }
        func elements(_ key: String) -> [BiobuzzFlowerElement] {
            (values[key] as? [String] ?? []).compactMap(BiobuzzFlowerElement.init(rawValue:))
        }
    }

    let match: ManualMatch
    private let alliances: [String: Alliance]

    init(_ name: String) throws {
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: BiobuzzFixture.url(name))) as? [String: Any]
        )
        let info = try XCTUnwrap(json["match"] as? [String: Any])
        let score = try XCTUnwrap(json["score"] as? [String: Any])
        let allianceList = try XCTUnwrap(score["alliances"] as? [[String: Any]])
        alliances = Dictionary(uniqueKeysWithValues: allianceList.map {
            (($0["alliance"] as? String) ?? "", Alliance(values: $0))
        })
        let stations = Dictionary(uniqueKeysWithValues: (info["teams"] as? [[String: Any]] ?? []).map {
            (($0["station"] as? String) ?? "", ($0["teamNumber"] as? Int) ?? 0)
        })
        let series = info["series"] as? Int ?? 0
        let number = info["matchNumber"] as? Int ?? 0

        var match = ManualMatch(
            level: series == 0 ? .qualification : .playoff,
            number: series == 0 ? number : series,
            game: series == 0 ? 1 : number,
            red1: stations["Red1"],
            red2: stations["Red2"],
            blue1: stations["Blue1"],
            blue2: stations["Blue2"],
            isScored: true,
            entryStyle: .detailed
        )
        for (key, alliance) in [("Red", AllianceColor.red), ("Blue", .blue)] {
            let values = try XCTUnwrap(alliances[key])
            var input = BiobuzzAllianceInput()
            input.autoHiveTips = values.int("autoHiveTips")
            input.autoRobot1Leave = values.bool("autoRobot1Leave")
            input.autoRobot2Leave = values.bool("autoRobot2Leave")
            input.autoRobot1Park = values.bool("autoRobot1Park")
            input.autoRobot2Park = values.bool("autoRobot2Park")
            input.teleopHiveTips = values.int("teleopHiveTips")
            input.teleopHivePollenNectar = values.int("teleopHivePollenNectar")
            input.teleopGardenPollenNectar = values.int("teleopGardenPollenNectar")
            input.teleopRobot1Park = values.bool("teleopRobot1Park")
            input.teleopRobot2Park = values.bool("teleopRobot2Park")
            input.minorFouls = values.int("minorFouls")
            input.majorFouls = values.int("majorFouls")
            if alliance == .red { match.red.biobuzz = input } else { match.blue.biobuzz = input }
        }
        let red = try XCTUnwrap(alliances["Red"])
        match.flowers = BiobuzzFlowers(
            redAlliance: red.elements("redAllianceFlower"),
            scoring: red.elements("scoringFlower"),
            blueAlliance: red.elements("blueAllianceFlower"),
            audience: red.elements("audienceFlower")
        )
        self.match = match
    }

    func alliance(_ color: AllianceColor) -> Alliance {
        alliances[color == .red ? "Red" : "Blue"]!
    }
}
