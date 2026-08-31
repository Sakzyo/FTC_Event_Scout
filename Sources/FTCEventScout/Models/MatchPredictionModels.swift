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
