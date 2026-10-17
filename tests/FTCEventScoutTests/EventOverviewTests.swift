import XCTest
@testable import FTCEventScout

final class EventOverviewTests: XCTestCase {
    func testLiveOverviewSummarizesTeamsMatchesLeaderAndHighScore() {
        let event = EventData(
            eventCode: "TEST",
            eventName: "Test Event",
            season: 2025,
            mode: .live,
            standings: [
                standing(teamNumber: 100, nonPenalty: 42.5),
                standing(teamNumber: 200, nonPenalty: 61.25),
                standing(teamNumber: 300, nonPenalty: nil),
            ],
            matches: [
                match(id: "q1", series: 0, number: 1, red: 120, blue: 95),
                match(id: "q2", series: 0, number: 2, red: 88, blue: 143),
                match(id: "q3", series: 0, number: 3, red: nil, blue: nil),
            ],
            statusMessage: ""
        )

        let stats = event.overviewStats

        XCTAssertEqual(stats.map(\.kind), [.teams, .matches, .topNonPenaltyOPR, .highScore])
        XCTAssertEqual(stats[0].value, 3)
        XCTAssertEqual(stats[1].value, 3)
        XCTAssertEqual(stats[1].detail, "2 played")
        XCTAssertEqual(stats[2].value, 61.25)
        XCTAssertEqual(stats[2].detail, "#200")
        XCTAssertEqual(stats[3].value, 143)
        XCTAssertEqual(stats[3].detail, "Q2 · Blue")
    }

    func testLiveOverviewOmitsPlayedDetailWhenEveryMatchHasScores() {
        let event = EventData(
            eventCode: "TEST",
            eventName: "Test Event",
            season: 2025,
            mode: .live,
            standings: [standing(teamNumber: 100)],
            matches: [match(id: "q1", series: 0, number: 1, red: 50, blue: 40)],
            statusMessage: ""
        )

        let matches = event.overviewStats.first { $0.kind == .matches }

        XCTAssertEqual(matches?.value, 1)
        XCTAssertNil(matches?.detail)
    }

    func testPreviewOverviewSummarizesRookiesAndHistoricalPeaks() {
        let event = EventData(
            eventCode: "TEST",
            eventName: "Test Event",
            season: 2025,
            mode: .preview,
            standings: [
                standing(teamNumber: 300, highest: 90, bestSeason: 2023, rookieYear: 2018),
                standing(teamNumber: 100, highest: 90, bestSeason: 2024, rookieYear: 2025),
                standing(teamNumber: 200, highest: 30, rookieYear: 2025),
                standing(teamNumber: 400, highest: nil, rookieYear: 2020),
            ],
            matches: [],
            statusMessage: ""
        )

        let stats = event.overviewStats

        XCTAssertEqual(stats.map(\.kind), [.teams, .rookies, .peakOPR, .averagePeakOPR])
        XCTAssertEqual(stats[0].value, 4)
        XCTAssertEqual(stats[1].value, 2)
        XCTAssertEqual(stats[2].value, 90)
        XCTAssertEqual(stats[2].detail, "#100 · 2024", "Ties go to the lower team number")
        XCTAssertEqual(stats[3].value, 70)
    }

    func testOverviewHandlesEventsWithoutData() {
        let event = EventData(
            eventCode: "TEST",
            eventName: "Test Event",
            season: 2025,
            mode: .live,
            standings: [],
            matches: [],
            statusMessage: ""
        )

        let stats = event.overviewStats

        XCTAssertEqual(stats[0].value, 0)
        XCTAssertNil(stats[1].detail)
        XCTAssertNil(stats[2].value)
        XCTAssertNil(stats[2].detail)
        XCTAssertNil(stats[3].value)
        XCTAssertNil(stats[3].detail)
    }

    func testSeriesLeaderAndAverageUseAvailableEntries() {
        let series = OPRChartSeries.make(from: [
            standing(teamNumber: 1, total: 10),
            standing(teamNumber: 2, total: 30),
            standing(teamNumber: 3, total: nil),
        ])

        let total = series.first { $0.metric == .total }
        let endgame = series.first { $0.metric == .endgame }

        XCTAssertEqual(total?.leader?.teamNumber, 2)
        XCTAssertEqual(total?.averageValue, 20)
        XCTAssertNil(endgame?.leader)
        XCTAssertNil(endgame?.averageValue)
    }

    func testMatchCompactTitlesDistinguishQualificationsPlayoffsAndUnknownSeries() {
        XCTAssertEqual(match(id: "q", series: 0, number: 12, red: nil, blue: nil).compactTitle, "Q12")
        XCTAssertEqual(match(id: "p", series: 3, number: 1, red: nil, blue: nil).compactTitle, "P3")
        XCTAssertEqual(match(id: "m", series: nil, number: 7, red: nil, blue: nil).compactTitle, "M7")
    }

    func testOPRChartLayoutPreferenceDefaultsToStackedAndRoundTrips() throws {
        let suiteName = "EventOverviewTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesService(defaults: defaults)

        XCTAssertEqual(preferences.oprChartLayout, .stacked)

        preferences.oprChartLayout = .focused
        XCTAssertEqual(PreferencesService(defaults: defaults).oprChartLayout, .focused)

        defaults.set("unknown", forKey: "oprChartLayout")
        XCTAssertEqual(preferences.oprChartLayout, .stacked)
    }

    private func standing(
        teamNumber: Int,
        total: Double? = nil,
        nonPenalty: Double? = nil,
        highest: Double? = nil,
        bestSeason: Int? = nil,
        rookieYear: Int? = nil
    ) -> TeamStanding {
        TeamStanding(
            teamNumber: teamNumber,
            storedRank: teamNumber,
            teamName: "Team \(teamNumber)",
            totalOPR: total,
            nonPenaltyOPR: nonPenalty,
            autoOPR: nil,
            teleopOPR: nil,
            endgameOPR: nil,
            highestOPR: highest,
            bestSeason: bestSeason,
            rookieYear: rookieYear,
            perSeason: [:]
        )
    }

    private func match(id: String, series: Double?, number: Double, red: Double?, blue: Double?) -> MatchRecord {
        MatchRecord(
            id: id,
            series: series,
            matchNumber: number,
            redTeams: [100, 200],
            blueTeams: [300, 400],
            redScore: score(red),
            blueScore: score(blue)
        )
    }

    private func score(_ value: Double?) -> ScoreBreakdown {
        ScoreBreakdown(
            autoScore: nil,
            teleopScore: nil,
            endgameScore: nil,
            foulScore: nil,
            foulCommitted: nil,
            majorFouls: nil,
            minorFouls: nil,
            finalScore: value,
            details: []
        )
    }
}
