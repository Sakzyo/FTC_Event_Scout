import XCTest
@testable import FTCEventScout

final class ManualCycleAverageTests: XCTestCase {
    private func perTeam(_ number: Int, red: (Int, Int), blue: (Int, Int), scored: Bool = true) -> ManualMatch {
        var match = ManualMatch(
            number: number,
            red1: red.0, red2: red.1, blue1: blue.0, blue2: blue.1,
            isScored: scored, entryStyle: .detailed, recording: .perTeam
        )
        match.red.biobuzz.robot1.autoHiveCycles = 1
        match.red.biobuzz.robot1.teleopHiveCycles = number
        return match
    }

    func testAveragesCountScoredPerTeamMatchesIncludingZeros() {
        let q1 = perTeam(1, red: (101, 102), blue: (201, 202)) // 101: 2 cycles
        let q2 = perTeam(2, red: (101, 201), blue: (102, 202)) // 101: 3 cycles
        var q3 = perTeam(3, red: (102, 101), blue: (201, 202)) // 102 is robot 1 here: 4 cycles
        q3.red.biobuzz.robot2.teleopHiveCycles = 5 // 101: 5 cycles
        let unscored = perTeam(4, red: (101, 102), blue: (201, 202), scored: false)
        var alliance = perTeam(5, red: (101, 102), blue: (201, 202))
        alliance.recording = .alliance
        var totals = perTeam(6, red: (101, 102), blue: (201, 202))
        totals.entryStyle = .totals

        let event = ManualEvent(name: "Cycles", season: 2026, matches: [q1, q2, q3, unscored, alliance, totals])
        let averages = ManualEventBuilder.cycleAverages(for: event)

        XCTAssertEqual(averages[101], (2 + 3 + 5) / 3)
        XCTAssertEqual(averages[102], 4.0 / 3) // 0, 0, 4
        XCTAssertEqual(averages[202], 0)
        XCTAssertEqual(ManualEventBuilder.eventData(for: event).teamCycleAverages, averages)
    }

    func testNoAveragesWithoutPerTeamEntry() {
        var match = perTeam(1, red: (101, 102), blue: (201, 202))
        match.recording = .alliance
        XCTAssertEqual(ManualEventBuilder.cycleAverages(for: ManualEvent(name: "A", season: 2026, matches: [match])), [:])
        XCTAssertEqual(ManualEventBuilder.cycleAverages(for: ManualEvent(name: "B", season: 2025, matches: [perTeam(1, red: (1, 2), blue: (3, 4))])), [:])
    }

    func testCycleColumnAndSortFieldFollowPlayed() {
        XCTAssertEqual(RankingSortField.liveFields(includingCycles: false), RankingSortField.liveFields)
        let fields = RankingSortField.liveFields(includingCycles: true)
        XCTAssertEqual(fields.firstIndex(of: .averageCycles), fields.firstIndex(of: .played).map { $0 + 1 })

        XCTAssertFalse(RankingColumn.live(sortField: .totalOPR).contains(.averageCycles))
        let columns = RankingColumn.live(sortField: .totalOPR, showsCycles: true)
        XCTAssertEqual(columns.firstIndex(of: .averageCycles), columns.firstIndex(of: .played).map { $0 + 1 })
        XCTAssertEqual(RankingColumn.averageCycles.sortField, .averageCycles)
        XCTAssertEqual(RankingSortField.averageCycles.defaultSortDirection, .descending)
    }

    func testCycleCellShowsTeamAverage() {
        let team = TeamStanding(
            teamNumber: 101, storedRank: 1, teamName: "", totalOPR: nil, nonPenaltyOPR: nil,
            autoOPR: nil, teleopOPR: nil, endgameOPR: nil, seasonOPR: nil, rookieYear: nil
        )
        let row = RankedStanding(order: 1, team: team)
        XCTAssertEqual(
            RankingColumn.averageCycles.value(for: row, records: [:], metrics: [:], cycleAverages: [101: 3.5]),
            .decimal(3.5)
        )
        XCTAssertEqual(RankingColumn.averageCycles.value(for: row, records: [:], metrics: [:]), .decimal(nil))
    }
}
