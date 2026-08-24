import XCTest
@testable import FTCEventScout

final class OPRChartSeriesTests: XCTestCase {
    func testSeriesUseRequestedMetricOrderAndKeepTheTopTenTeams() {
        let standings = (1 ... 12).map { teamNumber in
            standing(
                teamNumber: teamNumber,
                total: Double(teamNumber),
                nonPenalty: Double(teamNumber) + 10,
                auto: Double(teamNumber) + 20,
                teleop: Double(teamNumber) + 30,
                endgame: Double(teamNumber) + 40
            )
        }

        let series = OPRChartSeries.make(from: standings)

        XCTAssertEqual(series.map(\.metric), [.total, .nonPenalty, .teleop, .auto, .endgame])
        XCTAssertTrue(series.allSatisfy { $0.entries.count == 12 })
        XCTAssertTrue(series.allSatisfy { $0.summaryEntries.count == 10 })
        XCTAssertTrue(series.allSatisfy { $0.availableTeamCount == 12 })
        XCTAssertEqual(series[0].entries.map(\.teamNumber), Array((1 ... 12).reversed()))
        XCTAssertEqual(series[0].summaryEntries.map(\.teamNumber), Array((3 ... 12).reversed()))
        XCTAssertEqual(series[0].teamDomain, (1 ... 12).map(String.init))
        XCTAssertEqual(series[0].summaryTeamDomain, (3 ... 12).map(String.init))
    }

    func testSeriesSkipUnavailableAndNonFiniteValuesAndBreakTiesByTeamNumber() {
        let standings = [
            standing(teamNumber: 30, total: 5),
            standing(teamNumber: 10, total: 5),
            standing(teamNumber: 20, total: nil),
            standing(teamNumber: 40, total: .infinity),
        ]

        let totalSeries = OPRChartSeries.make(from: standings)[0]

        XCTAssertEqual(totalSeries.entries.map(\.teamNumber), [10, 30])
        XCTAssertEqual(totalSeries.availableTeamCount, 2)
    }

    func testValueDomainIncludesZeroAndPaddingForMixedSigns() {
        let standings = [
            standing(teamNumber: 1, total: -4),
            standing(teamNumber: 2, total: 8),
        ]

        let domain = OPRChartSeries.make(from: standings)[0].valueDomain

        XCTAssertLessThan(domain.lowerBound, -4)
        XCTAssertGreaterThan(domain.upperBound, 8)
        XCTAssertTrue(domain.contains(0))
    }

    func testTeamColorIdentityIsStableAndDistinctAcrossEventTeams() {
        let teamNumbers = [9755, 16095, 19603, 19705, 21981, 24599, 25218, 27570]
        let firstPass = teamNumbers.map(TeamChartColorIdentity.hue)
        let secondPass = teamNumbers.map(TeamChartColorIdentity.hue)

        XCTAssertEqual(firstPass, secondPass)
        XCTAssertEqual(Set(firstPass).count, teamNumbers.count)
        XCTAssertTrue(firstPass.allSatisfy { (0 ..< 1).contains($0) })
    }

    private func standing(
        teamNumber: Int,
        total: Double?,
        nonPenalty: Double? = nil,
        auto: Double? = nil,
        teleop: Double? = nil,
        endgame: Double? = nil
    ) -> TeamStanding {
        TeamStanding(
            teamNumber: teamNumber,
            storedRank: teamNumber,
            teamName: "Team \(teamNumber)",
            totalOPR: total,
            nonPenaltyOPR: nonPenalty,
            autoOPR: auto,
            teleopOPR: teleop,
            endgameOPR: endgame,
            highestOPR: nil,
            bestSeason: nil,
            rookieYear: nil,
            perSeason: [:]
        )
    }
}
