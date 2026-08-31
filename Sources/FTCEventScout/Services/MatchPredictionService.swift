import Foundation

enum IQRStatistics {
    static let minimumObservationCount = 4

    /// Uses R-7 linear interpolation: position = (count - 1) * percentile.
    /// Non-finite inputs are ignored so they cannot poison the bounds.
    static func percentile(_ percentile: Double, of values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty, (0 ... 1).contains(percentile) else { return nil }
        guard sorted.count > 1 else { return sorted[0] }

        let position = Double(sorted.count - 1) * percentile
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = Int(position.rounded(.up))
        guard lowerIndex != upperIndex else { return sorted[lowerIndex] }

        let fraction = position - Double(lowerIndex)
        return sorted[lowerIndex] + fraction * (sorted[upperIndex] - sorted[lowerIndex])
    }

    static func quartiles(of values: [Double]) -> (first: Double, third: Double)? {
        guard let first = percentile(0.25, of: values),
              let third = percentile(0.75, of: values) else {
            return nil
        }
        return (first, third)
    }

    static func bounds(for values: [Double]) -> IQRBounds? {
        guard let quartiles = quartiles(of: values) else { return nil }
        return IQRBounds(
            firstQuartile: quartiles.first,
            thirdQuartile: quartiles.third
        )
    }

    static func isOutlier(_ value: Double, using bounds: IQRBounds) -> Bool {
        guard value.isFinite else { return false }
        // Equality is deliberately retained, per the OPRc definition.
        return value < bounds.lowerBound || value > bounds.upperBound
    }
}

enum OPRCalculator {
    struct Result: Equatable {
        let valuesByTeam: [Int: Double]
        let rank: Int
        let teamCount: Int
    }

    static func calculate(from performances: [AlliancePerformance]) -> Result? {
        let validPerformances = performances.filter {
            $0.score.isFinite && !$0.teamNumbers.isEmpty
                && $0.teamNumbers.allSatisfy { $0 > 0 }
                && Set($0.teamNumbers).count == $0.teamNumbers.count
        }
        let teamNumbers = Array(Set(validPerformances.flatMap(\.teamNumbers))).sorted()
        guard !validPerformances.isEmpty, !teamNumbers.isEmpty else { return nil }

        let teamIndex = Dictionary(uniqueKeysWithValues: teamNumbers.enumerated().map {
            ($0.element, $0.offset)
        })
        var matrix = Array(
            repeating: Array(repeating: 0.0, count: teamNumbers.count),
            count: validPerformances.count
        )
        var scores = Array(repeating: 0.0, count: validPerformances.count)

        for (row, performance) in validPerformances.enumerated() {
            for teamNumber in performance.teamNumbers {
                guard let column = teamIndex[teamNumber] else { continue }
                matrix[row][column] = 1
            }
            scores[row] = performance.score
        }

        guard let solution = JacobiLeastSquaresSolver.solve(matrix: matrix, vector: scores) else {
            return nil
        }
        let values = Dictionary(uniqueKeysWithValues: teamNumbers.enumerated().compactMap {
            let value = solution.values[$0.offset]
            return value.isFinite ? ($0.element, value) : nil
        })
        return Result(valuesByTeam: values, rank: solution.rank, teamCount: teamNumbers.count)
    }
}

enum MatchPredictionService {
    static let minimumTeamAppearancesForReadyPrediction = 2

    /// FTC Event Scout receives only alliance scores, not legitimate per-robot
    /// match scores. OPRc therefore uses the requested residual fallback: solve
    /// baseline OPR, apply one IQR pass to alliance residuals, then solve again.
    static func analyze(matches: [MatchRecord]) -> OPRcAnalysis {
        let completed = validCompletedMatches(from: matches)
        let performances = completed.flatMap(alliancePerformances)
        let baseline = OPRCalculator.calculate(from: performances)

        let residuals: [(performance: AlliancePerformance, value: Double)] = performances.compactMap {
            performance in
            guard let values = baseline?.valuesByTeam,
                  let predicted = allianceScore(
                    for: performance.teamNumbers,
                    valuesByTeam: values
                  ) else { return nil }
            let residual = performance.score - predicted
            return residual.isFinite ? (performance, residual) : nil
        }

        let filteringWasApplied = residuals.count >= IQRStatistics.minimumObservationCount
        let residualBounds = filteringWasApplied
            ? IQRStatistics.bounds(for: residuals.map(\.value))
            : nil
        let excludedIDs: Set<String>
        if let residualBounds {
            excludedIDs = Set(residuals.compactMap {
                IQRStatistics.isOutlier($0.value, using: residualBounds)
                    ? $0.performance.id
                    : nil
            })
        } else {
            excludedIDs = []
        }

        let filteredPerformances = performances.filter { !excludedIDs.contains($0.id) }
        let filtered = OPRCalculator.calculate(from: filteredPerformances)
        let teamMetrics = makeTeamMetrics(
            baseline: baseline,
            filtered: filtered,
            performances: performances,
            filteredPerformances: filteredPerformances,
            excludedIDs: excludedIDs,
            filteringWasApplied: filteringWasApplied
        )
        let predictions = upcomingMatches(from: matches).map {
            prediction(
                for: $0,
                teamMetrics: teamMetrics,
                filteringWasApplied: filteringWasApplied,
                calculationIsRankDeficient: (filtered?.rank ?? 0) < (filtered?.teamCount ?? 0)
            )
        }

        return OPRcAnalysis(
            teamMetrics: teamMetrics,
            predictions: predictions,
            validCompletedMatchCount: completed.count,
            validAllianceObservationCount: performances.count,
            excludedOutlierCount: excludedIDs.count,
            filteringWasApplied: filteringWasApplied,
            residualBounds: residualBounds,
            baselineRank: baseline?.rank ?? 0,
            filteredRank: filtered?.rank ?? 0,
            baselineTeamCount: baseline?.teamCount ?? 0,
            filteredTeamCount: filtered?.teamCount ?? 0
        )
    }

    static func predict(
        matchID: String,
        displayTitle: String,
        series: Double?,
        matchNumber: Double?,
        redTeams: [Int],
        blueTeams: [Int],
        teamMetrics: [Int: TeamOPRcMetric],
        filteringWasApplied: Bool = true,
        calculationIsRankDeficient: Bool = false
    ) -> MatchPrediction {
        let match = MatchRecord(
            id: matchID,
            series: series,
            matchNumber: matchNumber,
            redTeams: redTeams,
            blueTeams: blueTeams,
            redScore: emptyScore,
            blueScore: emptyScore
        )
        return prediction(
            for: match,
            displayTitle: displayTitle,
            teamMetrics: teamMetrics,
            filteringWasApplied: filteringWasApplied,
            calculationIsRankDeficient: calculationIsRankDeficient
        )
    }

    private static func makeTeamMetrics(
        baseline: OPRCalculator.Result?,
        filtered: OPRCalculator.Result?,
        performances: [AlliancePerformance],
        filteredPerformances: [AlliancePerformance],
        excludedIDs: Set<String>,
        filteringWasApplied: Bool
    ) -> [Int: TeamOPRcMetric] {
        guard let baseline else { return [:] }
        return Dictionary(uniqueKeysWithValues: baseline.valuesByTeam.keys.sorted().compactMap {
            teamNumber in
            guard let opr = baseline.valuesByTeam[teamNumber], opr.isFinite else { return nil }
            let matchesUsed = filteredPerformances.count { $0.teamNumbers.contains(teamNumber) }
            let matchesExcluded = performances.count {
                excludedIDs.contains($0.id) && $0.teamNumbers.contains(teamNumber)
            }
            let oprc = filtered?.valuesByTeam[teamNumber].flatMap { $0.isFinite ? $0 : nil }
            return (
                teamNumber,
                TeamOPRcMetric(
                    teamNumber: teamNumber,
                    opr: opr,
                    oprc: oprc,
                    matchesUsed: matchesUsed,
                    matchesExcludedAsOutliers: matchesExcluded,
                    hasEnoughDataForOutlierFiltering: filteringWasApplied
                )
            )
        })
    }

    private static func prediction(
        for match: MatchRecord,
        displayTitle: String? = nil,
        teamMetrics: [Int: TeamOPRcMetric],
        filteringWasApplied: Bool,
        calculationIsRankDeficient: Bool
    ) -> MatchPrediction {
        let allTeams = match.redTeams + match.blueTeams
        let unavailableTeams = Array(Set(allTeams.filter {
            guard let value = teamMetrics[$0]?.oprc else { return true }
            return !value.isFinite
        })).sorted()
        let hasValidAlliances = !match.redTeams.isEmpty && !match.blueTeams.isEmpty
            && allTeams.allSatisfy { $0 > 0 }
            && Set(match.redTeams).count == match.redTeams.count
            && Set(match.blueTeams).count == match.blueTeams.count
            && Set(match.redTeams).isDisjoint(with: Set(match.blueTeams))

        guard hasValidAlliances, unavailableTeams.isEmpty else {
            return MatchPrediction(
                matchID: match.id,
                displayTitle: displayTitle ?? match.displayTitle,
                series: match.series,
                matchNumber: match.matchNumber,
                redTeams: match.redTeams,
                blueTeams: match.blueTeams,
                predictedRedScore: nil,
                predictedBlueScore: nil,
                predictedMargin: nil,
                predictedWinner: nil,
                status: .unavailable,
                unavailableTeamNumbers: unavailableTeams,
                limitedDataTeamNumbers: []
            )
        }

        guard let redScore = predictedScore(
            for: match.redTeams,
            teamMetrics: teamMetrics
        ), let blueScore = predictedScore(
            for: match.blueTeams,
            teamMetrics: teamMetrics
        ) else {
            return MatchPrediction(
                matchID: match.id,
                displayTitle: displayTitle ?? match.displayTitle,
                series: match.series,
                matchNumber: match.matchNumber,
                redTeams: match.redTeams,
                blueTeams: match.blueTeams,
                predictedRedScore: nil,
                predictedBlueScore: nil,
                predictedMargin: nil,
                predictedWinner: nil,
                status: .unavailable,
                unavailableTeamNumbers: unavailableTeams,
                limitedDataTeamNumbers: []
            )
        }
        let margin = redScore - blueScore
        let winner: PredictedMatchWinner = if margin > 0 {
            .red
        } else if margin < 0 {
            .blue
        } else {
            .tie
        }
        let limitedTeams = Array(Set(allTeams.filter {
            (teamMetrics[$0]?.matchesUsed ?? 0) < minimumTeamAppearancesForReadyPrediction
        })).sorted()
        let status: MatchPredictionStatus = if filteringWasApplied,
                                               !calculationIsRankDeficient,
                                               limitedTeams.isEmpty {
            .ready
        } else {
            .limitedData
        }

        return MatchPrediction(
            matchID: match.id,
            displayTitle: displayTitle ?? match.displayTitle,
            series: match.series,
            matchNumber: match.matchNumber,
            redTeams: match.redTeams,
            blueTeams: match.blueTeams,
            predictedRedScore: redScore,
            predictedBlueScore: blueScore,
            predictedMargin: margin,
            predictedWinner: winner,
            status: status,
            unavailableTeamNumbers: [],
            limitedDataTeamNumbers: limitedTeams
        )
    }

    private static func validCompletedMatches(from matches: [MatchRecord]) -> [MatchRecord] {
        var seen = Set<MatchIdentity>()
        return matches.filter { match in
            guard validScore(match.redScore.finalScore) != nil,
                  validScore(match.blueScore.finalScore) != nil,
                  validTeamNumbers(match.redTeams),
                  validTeamNumbers(match.blueTeams),
                  Set(match.redTeams).isDisjoint(with: Set(match.blueTeams)) else {
                return false
            }
            return seen.insert(MatchIdentity(match: match)).inserted
        }
    }

    private static func upcomingMatches(from matches: [MatchRecord]) -> [MatchRecord] {
        var seen = Set<MatchIdentity>()
        return matches.filter { match in
            guard validScore(match.redScore.finalScore) == nil
                    || validScore(match.blueScore.finalScore) == nil else {
                return false
            }
            return seen.insert(MatchIdentity(match: match)).inserted
        }
    }

    private static func alliancePerformances(for match: MatchRecord) -> [AlliancePerformance] {
        guard let redScore = validScore(match.redScore.finalScore),
              let blueScore = validScore(match.blueScore.finalScore) else {
            return []
        }
        return [
            AlliancePerformance(
                id: "\(match.id):red",
                matchID: match.id,
                series: match.series,
                matchNumber: match.matchNumber,
                alliance: .red,
                teamNumbers: match.redTeams,
                score: redScore
            ),
            AlliancePerformance(
                id: "\(match.id):blue",
                matchID: match.id,
                series: match.series,
                matchNumber: match.matchNumber,
                alliance: .blue,
                teamNumbers: match.blueTeams,
                score: blueScore
            ),
        ]
    }

    private static func validScore(_ score: Double?) -> Double? {
        guard let score, score.isFinite, score >= 0 else { return nil }
        return score
    }

    private static func validTeamNumbers(_ teamNumbers: [Int]) -> Bool {
        !teamNumbers.isEmpty
            && teamNumbers.allSatisfy { $0 > 0 }
            && Set(teamNumbers).count == teamNumbers.count
    }

    private static func allianceScore(
        for teamNumbers: [Int],
        valuesByTeam: [Int: Double]
    ) -> Double? {
        var total = 0.0
        for teamNumber in teamNumbers {
            guard let value = valuesByTeam[teamNumber], value.isFinite else { return nil }
            total += value
        }
        return total
    }

    private static func predictedScore(
        for teamNumbers: [Int],
        teamMetrics: [Int: TeamOPRcMetric]
    ) -> Double? {
        var total = 0.0
        for teamNumber in teamNumbers {
            guard let value = teamMetrics[teamNumber]?.oprc, value.isFinite else { return nil }
            total += value
        }
        return total
    }

    private static let emptyScore = ScoreBreakdown(
        autoScore: nil,
        teleopScore: nil,
        endgameScore: nil,
        foulScore: nil,
        foulCommitted: nil,
        majorFouls: nil,
        minorFouls: nil,
        finalScore: nil,
        details: []
    )
}

private struct MatchIdentity: Hashable {
    let series: Double?
    let matchNumber: Double?
    let redTeams: [Int]
    let blueTeams: [Int]
    let fallbackID: String?

    init(match: MatchRecord) {
        series = match.series?.isFinite == true ? match.series : nil
        matchNumber = match.matchNumber?.isFinite == true ? match.matchNumber : nil
        redTeams = match.redTeams.sorted()
        blueTeams = match.blueTeams.sorted()
        fallbackID = series == nil && matchNumber == nil ? match.id : nil
    }
}

private enum JacobiLeastSquaresSolver {
    struct Solution {
        let values: [Double]
        let rank: Int
    }

    /// One-sided Jacobi SVD. It orthogonalizes A directly (rather than forming
    /// AᵀA) and returns the deterministic Moore–Penrose least-squares solution.
    static func solve(matrix: [[Double]], vector: [Double]) -> Solution? {
        guard !matrix.isEmpty,
              let columnCount = matrix.first?.count,
              columnCount > 0,
              matrix.count == vector.count,
              matrix.allSatisfy({ $0.count == columnCount && $0.allSatisfy(\.isFinite) }),
              vector.allSatisfy(\.isFinite) else {
            return nil
        }

        let rowCount = matrix.count
        var columns = (0 ..< columnCount).map { column in
            matrix.map { $0[column] }
        }
        var rightSingularVectors = Array(
            repeating: Array(repeating: 0.0, count: columnCount),
            count: columnCount
        )
        for index in 0 ..< columnCount {
            rightSingularVectors[index][index] = 1
        }

        let correlationTolerance = 1e-12
        let maximumSweeps = 100
        if columnCount > 1 {
            for _ in 0 ..< maximumSweeps {
                var rotated = false
                for left in 0 ..< (columnCount - 1) {
                    for right in (left + 1) ..< columnCount {
                        let alpha = dot(columns[left], columns[left])
                        let beta = dot(columns[right], columns[right])
                        let gamma = dot(columns[left], columns[right])
                        guard alpha > 0, beta > 0,
                              abs(gamma) > correlationTolerance * sqrt(alpha * beta) else {
                            continue
                        }

                        let zeta = (beta - alpha) / (2 * gamma)
                        let tangent: Double
                        if zeta == 0 {
                            tangent = 1
                        } else {
                            let sign = zeta.sign == .minus ? -1.0 : 1.0
                            tangent = sign / (abs(zeta) + sqrt(1 + zeta * zeta))
                        }
                        let cosine = 1 / sqrt(1 + tangent * tangent)
                        let sine = cosine * tangent

                        rotateVectorPair(
                            &columns,
                            left: left,
                            right: right,
                            cosine: cosine,
                            sine: sine
                        )
                        rotateColumns(
                            &rightSingularVectors,
                            left: left,
                            right: right,
                            cosine: cosine,
                            sine: sine
                        )
                        rotated = true
                    }
                }
                if !rotated { break }
            }
        }

        let singularValues = columns.map { sqrt(max(dot($0, $0), 0)) }
        let maximumSingularValue = singularValues.max() ?? 0
        let rankTolerance = Double(max(rowCount, columnCount))
            * Double.ulpOfOne * maximumSingularValue * 32
        var values = Array(repeating: 0.0, count: columnCount)
        var rank = 0

        for singularIndex in 0 ..< columnCount {
            let singularValue = singularValues[singularIndex]
            guard singularValue > rankTolerance else { continue }
            rank += 1
            let coefficient = dot(columns[singularIndex], vector)
                / (singularValue * singularValue)
            for teamIndex in 0 ..< columnCount {
                values[teamIndex] += rightSingularVectors[teamIndex][singularIndex]
                    * coefficient
            }
        }

        return values.allSatisfy(\.isFinite) ? Solution(values: values, rank: rank) : nil
    }

    private static func dot(_ lhs: [Double], _ rhs: [Double]) -> Double {
        zip(lhs, rhs).reduce(0.0) { $0 + $1.0 * $1.1 }
    }

    private static func rotateColumns(
        _ matrix: inout [[Double]],
        left: Int,
        right: Int,
        cosine: Double,
        sine: Double
    ) {
        for row in matrix.indices {
            let leftValue = matrix[row][left]
            let rightValue = matrix[row][right]
            matrix[row][left] = cosine * leftValue - sine * rightValue
            matrix[row][right] = sine * leftValue + cosine * rightValue
        }
    }

    private static func rotateVectorPair(
        _ vectors: inout [[Double]],
        left: Int,
        right: Int,
        cosine: Double,
        sine: Double
    ) {
        for row in vectors[left].indices {
            let leftValue = vectors[left][row]
            let rightValue = vectors[right][row]
            vectors[left][row] = cosine * leftValue - sine * rightValue
            vectors[right][row] = sine * leftValue + cosine * rightValue
        }
    }
}
