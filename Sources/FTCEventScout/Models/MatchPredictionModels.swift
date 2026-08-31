import Foundation

enum PredictedMatchWinner: String, Equatable {
    case red
    case blue
    case tie
}

enum MatchPredictionStatus: String, Equatable {
    case ready
    case limitedData
    case unavailable
}

struct IQRBounds: Equatable {
    let firstQuartile: Double
    let thirdQuartile: Double
    let interquartileRange: Double
    let lowerBound: Double
    let upperBound: Double

    init(firstQuartile: Double, thirdQuartile: Double) {
        self.firstQuartile = firstQuartile
        self.thirdQuartile = thirdQuartile
        interquartileRange = thirdQuartile - firstQuartile
        lowerBound = firstQuartile - 1.5 * interquartileRange
        upperBound = thirdQuartile + 1.5 * interquartileRange
    }
}

struct TeamOPRcMetric: Equatable {
    let teamNumber: Int
    let opr: Double
    let oprc: Double?
    let matchesUsed: Int
    let matchesExcludedAsOutliers: Int
    let hasEnoughDataForOutlierFiltering: Bool
}

struct MatchPrediction: Identifiable, Equatable {
    let matchID: String
    let displayTitle: String
    let series: Double?
    let matchNumber: Double?
    let redTeams: [Int]
    let blueTeams: [Int]
    let predictedRedScore: Double?
    let predictedBlueScore: Double?
    let predictedMargin: Double?
    let predictedWinner: PredictedMatchWinner?
    let status: MatchPredictionStatus
    let unavailableTeamNumbers: [Int]
    let limitedDataTeamNumbers: [Int]

    var id: String { matchID }
}

enum ManualMatchEntryError: LocalizedError, Equatable {
    case incomplete
    case invalidTeamNumber
    case duplicateTeamNumber

    var errorDescription: String? {
        switch self {
        case .incomplete:
            "Enter all four team numbers."
        case .invalidTeamNumber:
            "Team numbers must be positive whole numbers."
        case .duplicateTeamNumber:
            "Each team may appear only once in a match."
        }
    }
}

struct ManualMatchEntry: Equatable {
    let redTeams: [Int]
    let blueTeams: [Int]

    static func parse(
        redTeamNumbers: [String],
        blueTeamNumbers: [String]
    ) throws -> ManualMatchEntry {
        guard redTeamNumbers.count == 2, blueTeamNumbers.count == 2 else {
            throw ManualMatchEntryError.incomplete
        }

        let rawTeamNumbers = redTeamNumbers + blueTeamNumbers
        guard rawTeamNumbers.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw ManualMatchEntryError.incomplete
        }

        let teamNumbers = try rawTeamNumbers.map { rawValue -> Int in
            let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let teamNumber = Int(normalized), teamNumber > 0 else {
                throw ManualMatchEntryError.invalidTeamNumber
            }
            return teamNumber
        }
        guard Set(teamNumbers).count == teamNumbers.count else {
            throw ManualMatchEntryError.duplicateTeamNumber
        }

        return ManualMatchEntry(
            redTeams: Array(teamNumbers.prefix(2)),
            blueTeams: Array(teamNumbers.suffix(2))
        )
    }
}

struct OPRcAnalysis: Equatable {
    let teamMetrics: [Int: TeamOPRcMetric]
    let predictions: [MatchPrediction]
    let validCompletedMatchCount: Int
    let validAllianceObservationCount: Int
    let excludedOutlierCount: Int
    let filteringWasApplied: Bool
    let residualBounds: IQRBounds?
    let baselineRank: Int
    let filteredRank: Int
    let baselineTeamCount: Int
    let filteredTeamCount: Int

    var baselineIsRankDeficient: Bool {
        baselineRank < baselineTeamCount
    }

    var filteredIsRankDeficient: Bool {
        filteredRank < filteredTeamCount
    }
}

struct AlliancePerformance: Equatable {
    let id: String
    let matchID: String
    let series: Double?
    let matchNumber: Double?
    let alliance: AllianceColor
    let teamNumbers: [Int]
    let score: Double
}
