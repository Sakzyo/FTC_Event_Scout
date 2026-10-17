import XCTest
@testable import FTCEventScout

final class RankingStatTableTests: XCTestCase {
    // MARK: Sorting

    func testMetricColumnsSortStrongestFirstAndIdentifiersAscend() {
        let ascending: [RankingSortField] = [.storedRank, .teamNumber, .teamName, .rookieYear]
        let descending: [RankingSortField] = [
            .totalOPR, .oprc, .nonPenaltyOPR, .autoOPR, .teleopOPR, .endgameOPR,
            .highestOPR, .bestSeason, .record, .played,
        ]

        XCTAssertEqual(Set(ascending + descending), Set(RankingSortField.allCases))
        for field in ascending {
            XCTAssertEqual(field.defaultSortDirection, .ascending, "\(field)")
        }
        for field in descending {
            XCTAssertEqual(field.defaultSortDirection, .descending, "\(field)")
        }
    }

    func testHeaderClickStartsNewColumnsInTheirNaturalDirection() {
        let next = RankingSortField.record.headerSort(currentField: .teamNumber, currentDirection: .ascending)

        XCTAssertEqual(next.field, .record)
        XCTAssertEqual(next.direction, .descending)
    }

    func testHeaderClickOnTheActiveColumnReversesIt() {
        let first = RankingSortField.totalOPR.headerSort(currentField: .totalOPR, currentDirection: .descending)
        let second = RankingSortField.totalOPR.headerSort(currentField: .totalOPR, currentDirection: first.direction)

        XCTAssertEqual(first.direction, .ascending)
        XCTAssertEqual(second.direction, .descending)
    }

    func testLiveSortFieldsIncludeRecordAndPlayed() {
        XCTAssertTrue(RankingSortField.liveFields.contains(.record))
        XCTAssertTrue(RankingSortField.liveFields.contains(.played))
        XCTAssertFalse(RankingSortField.previewFields.contains(.record))
    }

    // MARK: Columns

    func testLiveColumnsDropThePositionWhenSortedByEventRank() {
        let columns = RankingColumn.live(sortField: .storedRank)

        XCTAssertFalse(columns.contains(.order))
        XCTAssertEqual(Array(columns.prefix(5)), [.eventRank, .team, .tags, .record, .played])
        XCTAssertEqual(columns.count, 11)
    }

    func testLiveColumnsLeadWithThePositionForOtherSorts() {
        let columns = RankingColumn.live(sortField: .nonPenaltyOPR)

        XCTAssertEqual(columns.first, .order)
        XCTAssertEqual(columns.count, 12)
        XCTAssertEqual(columns.last, .metric(.endgameOPR))
    }

    func testPreviewColumnsShowTheLastThreeSeasons() {
        let columns = RankingColumn.preview(season: 2025)

        XCTAssertEqual(
            columns.filter { if case .seasonOPR = $0 { true } else { false } },
            [.seasonOPR(2025), .seasonOPR(2024), .seasonOPR(2023)]
        )
        XCTAssertEqual(RankingColumn.seasonOPR(2024).title, "2024")
    }

    func testColumnsAreColorGroupedLikeFTCScout() {
        XCTAssertEqual(RankingColumn.team.color, .white)
        XCTAssertEqual(RankingColumn.eventRank.color, .white)
        XCTAssertEqual(RankingColumn.record.color, .green)
        XCTAssertEqual(RankingColumn.played.color, .green)
        XCTAssertEqual(RankingColumn.metric(.oprc).color, .purple)
        XCTAssertEqual(RankingColumn.metric(.highestOPR).color, .blue)
        XCTAssertEqual(RankingColumn.bestSeason.color, .lightBlue)
        XCTAssertNil(ScoutStatColor.white.cellTint)
        XCTAssertNotNil(ScoutStatColor.purple.cellTint)
    }

    func testOnlyDerivedColumnsAreUnsortable() {
        XCTAssertNil(RankingColumn.order.sortField)
        XCTAssertNil(RankingColumn.tags.sortField)
        XCTAssertNil(RankingColumn.seasonOPR(2024).sortField)
        XCTAssertEqual(RankingColumn.eventRank.sortField, .storedRank)
        XCTAssertEqual(RankingColumn.team.sortField, .teamNumber)
        XCTAssertEqual(RankingColumn.record.sortField, .record)
        XCTAssertEqual(RankingColumn.metric(.autoOPR).sortField, .autoOPR)
    }

    // MARK: Layout

    func testLayoutFillsWideViewportsWithoutWideningThePosition() {
        let columns = RankingColumn.live(sortField: .totalOPR)
        let base = RankingColumnLayout(columns: columns, availableWidth: 0, showsTeamNames: false)
        let wide = RankingColumnLayout(columns: columns, availableWidth: base.totalWidth + 300, showsTeamNames: false)

        XCTAssertEqual(wide.totalWidth, base.totalWidth + 300, accuracy: 0.001)
        XCTAssertEqual(wide.width(for: .order), base.width(for: .order))
        XCTAssertGreaterThan(wide.width(for: .metric(.totalOPR)), base.width(for: .metric(.totalOPR)))
        let sum = columns.reduce(CGFloat(0)) { $0 + wide.width(for: $1) }
        XCTAssertEqual(sum, wide.totalWidth, accuracy: 0.001)
    }

    func testLayoutKeepsBaseWidthsInNarrowViewports() {
        let columns = RankingColumn.preview(season: 2025)
        let layout = RankingColumnLayout(columns: columns, availableWidth: 200, showsTeamNames: true)

        XCTAssertEqual(layout.width(for: .team), RankingColumn.team.baseWidth(showsTeamNames: true))
        XCTAssertGreaterThan(layout.totalWidth, 200)
    }

    // MARK: Records

    func testRecordsCountScoredQualificationMatchesOnly() {
        let matches: [MatchRecord] = [
            match("Q1", series: 0, red: 50, blue: 40),
            match("Q2", series: 0, red: 30, blue: 30),
            match("Q3", series: 0, red: 10, blue: 60),
            match("Q4", series: 0, red: nil, blue: 60),
            match("M5", series: nil, red: 70, blue: 20),
            match("P1", series: 1, red: 90, blue: 10),
        ]

        let records = TeamEventRecord.make(from: matches)

        XCTAssertEqual(records[100], TeamEventRecord(wins: 2, losses: 1, ties: 1))
        XCTAssertEqual(records[300], TeamEventRecord(wins: 1, losses: 2, ties: 1))
        XCTAssertEqual(records[100]?.played, 4)
        XCTAssertEqual(records[100]?.displayText, "2-1-1")
        XCTAssertNil(records[999])
    }

    func testRecordsCompareByWinRateThenWins() {
        let strong = TeamEventRecord(wins: 5, losses: 1, ties: 0)
        let tiedRate = TeamEventRecord(wins: 10, losses: 2, ties: 0)
        let weak = TeamEventRecord(wins: 1, losses: 5, ties: 0)
        let unplayed = TeamEventRecord()

        XCTAssertLessThan(weak, strong)
        XCTAssertLessThan(strong, tiedRate)
        XCTAssertLessThan(unplayed, weak)
        XCTAssertNil(unplayed.winRate)
        XCTAssertEqual(TeamEventRecord(wins: 1, losses: 0, ties: 1).winRate, 0.75)
    }

    func testRecordCellsShowUnavailableBeforeAnyScoredMatch() {
        let row = RankedStanding(order: 1, team: standing(100))
        let records: [Int: TeamEventRecord] = [200: TeamEventRecord(wins: 1, losses: 0, ties: 0)]

        XCTAssertEqual(RankingColumn.record.value(for: row, records: records, metrics: [:]), .record(nil))
        XCTAssertEqual(RankingColumn.played.value(for: row, records: records, metrics: [:]), .count(0))
        XCTAssertEqual(RankingCellValue.record(nil).accessibilityText, "Unavailable")
    }

    func testCellValuesReadFromTheirSources() {
        let row = RankedStanding(order: 3, team: standing(100, total: 42.5))
        let records: [Int: TeamEventRecord] = [100: TeamEventRecord(wins: 3, losses: 1, ties: 0)]
        let metric = TeamOPRcMetric(
            teamNumber: 100,
            opr: 42.5,
            oprc: 40.25,
            matchesUsed: 4,
            matchesExcludedAsOutliers: 0,
            hasEnoughDataForOutlierFiltering: true
        )
        let metrics: [Int: TeamOPRcMetric] = [100: metric]

        XCTAssertEqual(RankingColumn.order.value(for: row, records: records, metrics: metrics), .position(3))
        XCTAssertEqual(RankingColumn.eventRank.value(for: row, records: records, metrics: metrics), .ordinal(100))
        XCTAssertEqual(RankingColumn.metric(.totalOPR).value(for: row, records: records, metrics: metrics), .decimal(42.5))
        XCTAssertEqual(RankingColumn.metric(.oprc).value(for: row, records: records, metrics: metrics), .decimal(40.25))
        XCTAssertEqual(RankingColumn.metric(.autoOPR).value(for: row, records: records, metrics: metrics), .decimal(nil))
        XCTAssertEqual(RankingColumn.played.value(for: row, records: records, metrics: metrics), .count(4))
    }

    func testOrdinalsUseEnglishSuffixes() {
        let locale = Locale(identifier: "en_US")
        let values: [Int] = [1, 2, 3, 4, 11, 12, 13, 21, 22, 103]
        let expected: [String] = ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "103rd"]

        XCTAssertEqual(values.map { ScoutFormat.ordinal($0, locale: locale) }, expected)
    }

    // MARK: Helpers

    private func standing(_ teamNumber: Int, total: Double? = nil) -> TeamStanding {
        TeamStanding(
            teamNumber: teamNumber,
            storedRank: teamNumber,
            teamName: "",
            totalOPR: total,
            nonPenaltyOPR: nil,
            autoOPR: nil,
            teleopOPR: nil,
            endgameOPR: nil,
            highestOPR: nil,
            bestSeason: nil,
            rookieYear: nil,
            perSeason: [:]
        )
    }

    private func match(_ id: String, series: Double?, red: Double?, blue: Double?) -> MatchRecord {
        MatchRecord(
            id: id,
            series: series,
            matchNumber: 1,
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
