import XCTest
@testable import FTCEventScout

final class MatchPredictionServiceTests: XCTestCase {
    func testR7QuartilesAndIQRBounds() throws {
        let bounds = try XCTUnwrap(IQRStatistics.bounds(for: [1, 2, 3, 4, 5, 6, 7, 8]))

        XCTAssertEqual(bounds.firstQuartile, 2.75, accuracy: 1e-12)
        XCTAssertEqual(bounds.thirdQuartile, 6.25, accuracy: 1e-12)
        XCTAssertEqual(bounds.interquartileRange, 3.5, accuracy: 1e-12)
        XCTAssertEqual(bounds.lowerBound, -2.5, accuracy: 1e-12)
        XCTAssertEqual(bounds.upperBound, 11.5, accuracy: 1e-12)
    }

    func testLowerAndUpperOutliersAreDetected() throws {
        let lowBounds = try XCTUnwrap(IQRStatistics.bounds(for: [0, 10, 11, 12, 13]))
        XCTAssertTrue(IQRStatistics.isOutlier(0, using: lowBounds))
        XCTAssertFalse(IQRStatistics.isOutlier(10, using: lowBounds))

        let highBounds = try XCTUnwrap(IQRStatistics.bounds(for: [10, 11, 12, 13, 100]))
        XCTAssertTrue(IQRStatistics.isOutlier(100, using: highBounds))
        XCTAssertFalse(IQRStatistics.isOutlier(13, using: highBounds))
    }

    func testValuesExactlyOnOutlierBoundsAreRetained() {
        let bounds = IQRBounds(firstQuartile: 4, thirdQuartile: 8)

        XCTAssertEqual(bounds.lowerBound, -2)
        XCTAssertEqual(bounds.upperBound, 14)
        XCTAssertFalse(IQRStatistics.isOutlier(-2, using: bounds))
        XCTAssertFalse(IQRStatistics.isOutlier(14, using: bounds))
        XCTAssertTrue(IQRStatistics.isOutlier(-2.01, using: bounds))
        XCTAssertTrue(IQRStatistics.isOutlier(14.01, using: bounds))
    }

    func testOrdinaryAndRepeatedDatasetsRemainIntact() throws {
        let ordinary = try XCTUnwrap(IQRStatistics.bounds(for: [10, 11, 12, 13, 14, 15]))
        XCTAssertFalse([10, 11, 12, 13, 14, 15].contains {
            IQRStatistics.isOutlier(Double($0), using: ordinary)
        })

        let repeated = try XCTUnwrap(IQRStatistics.bounds(for: [7, 7, 7, 7, 7]))
        XCTAssertEqual(repeated.interquartileRange, 0)
        XCTAssertFalse(IQRStatistics.isOutlier(7, using: repeated))
    }

    func testQuartilesHandleSmallAndNonFiniteInputsDeterministically() throws {
        XCTAssertNil(IQRStatistics.quartiles(of: []))
        let one = try XCTUnwrap(IQRStatistics.quartiles(of: [5]))
        XCTAssertEqual(one.first, 5)
        XCTAssertEqual(one.third, 5)
        let two = try XCTUnwrap(IQRStatistics.quartiles(of: [1, 3]))
        XCTAssertEqual(two.first, 1.5)
        XCTAssertEqual(two.third, 2.5)
        let three = try XCTUnwrap(IQRStatistics.quartiles(of: [1, 2, 3]))
        XCTAssertEqual(three.first, 1.5)
        XCTAssertEqual(three.third, 2.5)
        let finiteOnly = try XCTUnwrap(IQRStatistics.quartiles(of: [1, 2, .nan, 3, .infinity, 4]))
        XCTAssertEqual(finiteOnly.first, 1.75)
        XCTAssertEqual(finiteOnly.third, 3.25)
    }

    func testLeastSquaresRecoversKnownOPRValues() throws {
        let performances = [
            performance("12", teams: [1, 2], score: 90),
            performance("13", teams: [1, 3], score: 80),
            performance("14", teams: [1, 4], score: 70),
            performance("23", teams: [2, 3], score: 70),
            performance("24", teams: [2, 4], score: 60),
            performance("34", teams: [3, 4], score: 50),
        ]

        let result = try XCTUnwrap(OPRCalculator.calculate(from: performances))

        XCTAssertEqual(result.rank, 4)
        XCTAssertEqual(result.valuesByTeam[1] ?? .nan, 50, accuracy: 1e-8)
        XCTAssertEqual(result.valuesByTeam[2] ?? .nan, 40, accuracy: 1e-8)
        XCTAssertEqual(result.valuesByTeam[3] ?? .nan, 30, accuracy: 1e-8)
        XCTAssertEqual(result.valuesByTeam[4] ?? .nan, 20, accuracy: 1e-8)
    }

    func testRankDeficientLeastSquaresReturnsFiniteMinimumNormSolution() throws {
        let result = try XCTUnwrap(OPRCalculator.calculate(from: [
            performance("only", teams: [1, 2], score: 90),
        ]))
        let first = try XCTUnwrap(result.valuesByTeam[1])
        let second = try XCTUnwrap(result.valuesByTeam[2])

        XCTAssertEqual(result.rank, 1)
        XCTAssertEqual(first, 45, accuracy: 1e-8)
        XCTAssertEqual(second, 45, accuracy: 1e-8)
        XCTAssertEqual(first + second, 90, accuracy: 1e-8)
        XCTAssertTrue(first.isFinite && second.isFinite)
    }

    func testOPRcRemovesAbnormalResidualAndMovesTowardUnderlyingStrength() throws {
        var matches = normalRoundRobinMatches(repetitions: 4)
        let number = matches.count + 1
        matches.append(match(number, red: [1, 2], redScore: 390, blue: [3, 4], blueScore: 50))

        let analysis = MatchPredictionService.analyze(matches: matches)
        let metric = try XCTUnwrap(analysis.teamMetrics[1])
        let corrected = try XCTUnwrap(metric.oprc)

        XCTAssertTrue(analysis.filteringWasApplied)
        XCTAssertGreaterThanOrEqual(analysis.excludedOutlierCount, 1)
        XCTAssertGreaterThan(metric.matchesExcludedAsOutliers, 0)
        XCTAssertGreaterThan(abs(metric.opr - 50), 1)
        XCTAssertLessThan(abs(corrected - 50), abs(metric.opr - 50))
    }

    func testOPRcAlsoRemovesStrongLowResidual() throws {
        var matches = normalRoundRobinMatches(repetitions: 4)
        let number = matches.count + 1
        matches.append(match(number, red: [1, 2], redScore: 0, blue: [3, 4], blueScore: 50))

        let analysis = MatchPredictionService.analyze(matches: matches)
        let metric = try XCTUnwrap(analysis.teamMetrics[1])

        XCTAssertGreaterThanOrEqual(analysis.excludedOutlierCount, 1)
        XCTAssertGreaterThan(metric.matchesExcludedAsOutliers, 0)
        XCTAssertNotNil(metric.oprc)
    }

    func testPredictionSumsOPRcAndCalculatesWinnerAndSignedMargin() throws {
        let prediction = MatchPredictionService.predict(
            matchID: "q24",
            displayTitle: "Qualification - 24",
            series: 0,
            matchNumber: 24,
            redTeams: [1, 2],
            blueTeams: [3, 4],
            teamMetrics: metrics([1: 50, 2: 40, 3: 45, 4: 35])
        )

        XCTAssertEqual(prediction.status, .ready)
        XCTAssertEqual(try XCTUnwrap(prediction.predictedRedScore), 90, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(prediction.predictedBlueScore), 80, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(prediction.predictedMargin), 10, accuracy: 1e-12)
        XCTAssertEqual(prediction.predictedWinner, .red)
    }

    func testIdenticalPredictedScoresProduceTie() {
        let prediction = MatchPredictionService.predict(
            matchID: "tie",
            displayTitle: "Qualification - 1",
            series: 0,
            matchNumber: 1,
            redTeams: [1, 2],
            blueTeams: [3, 4],
            teamMetrics: metrics([1: 50, 2: 40, 3: 45, 4: 45])
        )

        XCTAssertEqual(prediction.predictedRedScore, 90)
        XCTAssertEqual(prediction.predictedBlueScore, 90)
        XCTAssertEqual(prediction.predictedMargin, 0)
        XCTAssertEqual(prediction.predictedWinner, .tie)
    }

    func testPredictionUsesEveryTeamActuallyListedOnAnAlliance() {
        let prediction = MatchPredictionService.predict(
            matchID: "variable-alliance-size",
            displayTitle: "Test Match",
            series: nil,
            matchNumber: nil,
            redTeams: [1, 2, 3],
            blueTeams: [4, 5],
            teamMetrics: metrics([1: 10, 2: 20, 3: 30, 4: 25, 5: 25])
        )

        XCTAssertEqual(prediction.predictedRedScore, 60)
        XCTAssertEqual(prediction.predictedBlueScore, 50)
        XCTAssertEqual(prediction.predictedWinner, .red)
    }

    func testManualFourTeamEntryGeneratesTheSamePrediction() throws {
        let entry = try ManualMatchEntry.parse(
            redTeamNumbers: [" 1 ", "2"],
            blueTeamNumbers: ["3", "4"]
        )

        let prediction = MatchPredictionService.predict(
            matchID: "custom-match",
            displayTitle: "Custom Match",
            series: nil,
            matchNumber: nil,
            redTeams: entry.redTeams,
            blueTeams: entry.blueTeams,
            teamMetrics: metrics([1: 50, 2: 40, 3: 45, 4: 35])
        )

        XCTAssertEqual(entry.redTeams, [1, 2])
        XCTAssertEqual(entry.blueTeams, [3, 4])
        XCTAssertEqual(prediction.predictedRedScore, 90)
        XCTAssertEqual(prediction.predictedBlueScore, 80)
        XCTAssertEqual(prediction.predictedWinner, .red)
        XCTAssertEqual(prediction.predictedMargin, 10)
    }

    func testManualFourTeamEntryRejectsMissingInvalidAndDuplicateTeams() {
        assertManualEntryError(
            .incomplete,
            red: ["1", ""],
            blue: ["3", "4"]
        )
        assertManualEntryError(
            .invalidTeamNumber,
            red: ["1", "abc"],
            blue: ["3", "4"]
        )
        assertManualEntryError(
            .invalidTeamNumber,
            red: ["1", "0"],
            blue: ["3", "4"]
        )
        assertManualEntryError(
            .duplicateTeamNumber,
            red: ["1", "2"],
            blue: ["1", "4"]
        )
    }

    func testUnknownTeamMakesPredictionUnavailableWithoutUsingZero() {
        let prediction = MatchPredictionService.predict(
            matchID: "missing",
            displayTitle: "Qualification - 2",
            series: 0,
            matchNumber: 2,
            redTeams: [1, 999],
            blueTeams: [3, 4],
            teamMetrics: metrics([1: 50, 3: 45, 4: 35])
        )

        XCTAssertEqual(prediction.status, .unavailable)
        XCTAssertEqual(prediction.unavailableTeamNumbers, [999])
        XCTAssertNil(prediction.predictedRedScore)
        XCTAssertNil(prediction.predictedMargin)
        XCTAssertNil(prediction.predictedWinner)
    }

    func testSmallSampleRetainsAllObservationsAndMarksPredictionLimited() throws {
        let completed = match(1, red: [1, 2], redScore: 90, blue: [3, 4], blueScore: 80)
        let upcoming = match(2, red: [1, 2], redScore: nil, blue: [3, 4], blueScore: nil)

        let analysis = MatchPredictionService.analyze(matches: [completed, upcoming])
        let prediction = try XCTUnwrap(analysis.predictions.first)

        XCTAssertFalse(analysis.filteringWasApplied)
        XCTAssertNil(analysis.residualBounds)
        XCTAssertEqual(analysis.excludedOutlierCount, 0)
        XCTAssertEqual(analysis.validAllianceObservationCount, 2)
        XCTAssertEqual(prediction.status, .limitedData)
        XCTAssertNotNil(prediction.predictedRedScore)
    }

    func testDuplicateAndIncompleteMatchesAreExcludedFromOPR() {
        let completed = match(1, red: [1, 2], redScore: 90, blue: [3, 4], blueScore: 80)
        let duplicate = match(1, red: [1, 2], redScore: 90, blue: [3, 4], blueScore: 80)
        let incomplete = match(2, red: [1, 3], redScore: 80, blue: [2, 4], blueScore: nil)

        let analysis = MatchPredictionService.analyze(matches: [completed, duplicate, incomplete])

        XCTAssertEqual(analysis.validCompletedMatchCount, 1)
        XCTAssertEqual(analysis.validAllianceObservationCount, 2)
        XCTAssertEqual(analysis.predictions.count, 1)
    }

    func testInvalidScoresAreNeverUsedAsCompletedObservations() {
        let negative = match(1, red: [1, 2], redScore: -1, blue: [3, 4], blueScore: 80)
        let nonFinite = match(2, red: [1, 2], redScore: .infinity, blue: [3, 4], blueScore: 80)

        let analysis = MatchPredictionService.analyze(matches: [negative, nonFinite])

        XCTAssertEqual(analysis.validCompletedMatchCount, 0)
        XCTAssertEqual(analysis.validAllianceObservationCount, 0)
        XCTAssertTrue(analysis.teamMetrics.isEmpty)
        XCTAssertTrue(analysis.predictions.allSatisfy { $0.status == .unavailable })
    }

    func testEventDataRecomputesAnalysisWhenRefreshedMatchesBecomeFinal() {
        let completed = match(1, red: [1, 2], redScore: 90, blue: [3, 4], blueScore: 80)
        let scheduled = match(2, red: [1, 3], redScore: nil, blue: [2, 4], blueScore: nil)
        let refreshedFinal = match(2, red: [1, 3], redScore: 85, blue: [2, 4], blueScore: 75)

        let beforeRefresh = event(matches: [completed, scheduled])
        let afterRefresh = event(matches: [completed, refreshedFinal])

        XCTAssertEqual(beforeRefresh.oprcAnalysis.validCompletedMatchCount, 1)
        XCTAssertEqual(beforeRefresh.oprcAnalysis.predictions.map(\.matchID), [scheduled.id])
        XCTAssertEqual(afterRefresh.oprcAnalysis.validCompletedMatchCount, 2)
        XCTAssertTrue(afterRefresh.oprcAnalysis.predictions.isEmpty)
    }

    private func performance(
        _ id: String,
        teams: [Int],
        score: Double
    ) -> AlliancePerformance {
        AlliancePerformance(
            id: id,
            matchID: id,
            series: 0,
            matchNumber: 1,
            alliance: .red,
            teamNumbers: teams,
            score: score
        )
    }

    private func assertManualEntryError(
        _ expected: ManualMatchEntryError,
        red: [String],
        blue: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try ManualMatchEntry.parse(
                redTeamNumbers: red,
                blueTeamNumbers: blue
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? ManualMatchEntryError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func normalRoundRobinMatches(repetitions: Int) -> [MatchRecord] {
        var matches: [MatchRecord] = []
        var number = 1
        for _ in 0 ..< repetitions {
            matches.append(match(number, red: [1, 2], redScore: 90, blue: [3, 4], blueScore: 50))
            number += 1
            matches.append(match(number, red: [1, 3], redScore: 80, blue: [2, 4], blueScore: 60))
            number += 1
            matches.append(match(number, red: [1, 4], redScore: 70, blue: [2, 3], blueScore: 70))
            number += 1
        }
        return matches
    }

    private func metrics(_ values: [Int: Double]) -> [Int: TeamOPRcMetric] {
        Dictionary(uniqueKeysWithValues: values.map { teamNumber, value in
            (
                teamNumber,
                TeamOPRcMetric(
                    teamNumber: teamNumber,
                    opr: value,
                    oprc: value,
                    matchesUsed: 5,
                    matchesExcludedAsOutliers: 0,
                    hasEnoughDataForOutlierFiltering: true
                )
            )
        })
    }

    private func match(
        _ number: Int,
        red: [Int],
        redScore: Double?,
        blue: [Int],
        blueScore: Double?
    ) -> MatchRecord {
        MatchRecord(
            id: "qualification-\(number)",
            series: 0,
            matchNumber: Double(number),
            redTeams: red,
            blueTeams: blue,
            redScore: score(redScore),
            blueScore: score(blueScore)
        )
    }

    private func event(matches: [MatchRecord]) -> EventData {
        EventData(
            eventCode: "TEST",
            eventName: "Test Event",
            season: 2025,
            mode: .live,
            standings: [],
            matches: matches,
            statusMessage: "Test"
        )
    }

    private func score(_ finalScore: Double?) -> ScoreBreakdown {
        ScoreBreakdown(
            autoScore: nil,
            teleopScore: nil,
            endgameScore: nil,
            foulScore: nil,
            foulCommitted: nil,
            majorFouls: nil,
            minorFouls: nil,
            finalScore: finalScore,
            details: []
        )
    }
}
