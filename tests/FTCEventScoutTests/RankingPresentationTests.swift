import XCTest
@testable import FTCEventScout

final class RankingPresentationTests: XCTestCase {
    func testEveryRankingActionHasAStableDistinctPresentationIdentity() throws {
        let selection = TeamSelection(eventCode: "CNCMPLB", teamNumber: 24068)
        let series = try XCTUnwrap(OPRChartSeries.make(from: [standing]).first)

        let matches = RankingPresentation.matches(selection)
        let tags = RankingPresentation.tags(selection)
        let chart = RankingPresentation.chart(series)

        XCTAssertEqual(matches.id, "matches:CNCMPLB-24068")
        XCTAssertEqual(tags.id, "tags:CNCMPLB-24068")
        XCTAssertEqual(chart.id, "chart:total")
        XCTAssertEqual(Set([matches.id, tags.id, chart.id]).count, 3)
    }

    func testConvenienceFactoriesPreserveTheSelectedTeam() {
        XCTAssertEqual(
            RankingPresentation.matches(eventCode: "TEST", teamNumber: 1234),
            .matches(TeamSelection(eventCode: "TEST", teamNumber: 1234))
        )
        XCTAssertEqual(
            RankingPresentation.tags(eventCode: "TEST", teamNumber: 5678),
            .tags(TeamSelection(eventCode: "TEST", teamNumber: 5678))
        )
    }

    private var standing: TeamStanding {
        TeamStanding(
            teamNumber: 24068,
            storedRank: 1,
            teamName: "",
            totalOPR: 157.1,
            nonPenaltyOPR: 169.7,
            autoOPR: 27.6,
            teleopOPR: 104.2,
            endgameOPR: 7.2,
            highestOPR: nil,
            bestSeason: nil,
            rookieYear: nil,
            perSeason: [:]
        )
    }
}
