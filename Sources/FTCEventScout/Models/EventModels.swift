import Foundation

enum DashboardSection: String, CaseIterable, Identifiable {
    case rankings
    case highlights

    var id: String { rawValue }
}

enum EventMode: Equatable {
    case live
    case preview
}

enum EventLoadState: Equatable {
    case empty
    case loading(String)
    case loaded
    case failed(String)
}

enum RankingSortField: String, CaseIterable, Identifiable {
    case storedRank
    case teamNumber
    case totalOPR
    case nonPenaltyOPR
    case autoOPR
    case teleopOPR
    case endgameOPR
    case teamName
    case highestOPR
    case bestSeason
    case rookieYear

    var id: String { rawValue }

    static let liveFields: [RankingSortField] = [
        .storedRank, .teamNumber, .totalOPR, .nonPenaltyOPR,
        .autoOPR, .teleopOPR, .endgameOPR,
    ]

    static let previewFields: [RankingSortField] = [
        .storedRank, .teamNumber, .teamName, .highestOPR,
        .bestSeason, .rookieYear,
    ]
}

enum SortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }
}

struct HistoricalSeasonOPR: Decodable, Equatable, Hashable {
    let total: Double?
    let rank: Int?
    let auto: Double?
    let driverControlled: Double?

    private enum CodingKeys: String, CodingKey {
        case total = "tot"
        case rank
        case auto
        case driverControlled = "dc"
    }

    init(total: Double?, rank: Int?, auto: Double?, driverControlled: Double?) {
        self.total = total
        self.rank = rank
        self.auto = auto
        self.driverControlled = driverControlled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decodeIfPresent(Double.self, forKey: .total)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank)
        auto = try container.decodeIfPresent(Double.self, forKey: .auto)
        driverControlled = try container.decodeIfPresent(Double.self, forKey: .driverControlled)
    }
}

struct TeamStanding: Identifiable, Equatable, Hashable {
    let teamNumber: Int
    let storedRank: Int
    let teamName: String
    let totalOPR: Double?
    let nonPenaltyOPR: Double?
    let autoOPR: Double?
    let teleopOPR: Double?
    let endgameOPR: Double?
    let highestOPR: Double?
    let bestSeason: Int?
    let rookieYear: Int?
    let perSeason: [String: HistoricalSeasonOPR]

    var id: Int { teamNumber }
}

struct RankedStanding: Identifiable, Equatable {
    let order: Int
    let team: TeamStanding

    var id: Int { team.id }
}

enum AllianceColor: String, Equatable, Hashable {
    case red
    case blue
}

struct ScoreBreakdown: Equatable, Hashable {
    let autoScore: Double?
    let autoArtifactPoints: Double?
    let autoClassifiedArtifacts: Double?
    let autoOverflowArtifacts: Double?
    let autoPatternPoints: Double?
    let autoLeavePoints: Double?
    let teleopScore: Double?
    let teleopArtifactPoints: Double?
    let teleopClassifiedArtifacts: Double?
    let teleopOverflowArtifacts: Double?
    let teleopPatternPoints: Double?
    let teleopDepotPoints: Double?
    let endgameScore: Double?
    let foulScore: Double?
    let foulCommitted: Double?
    let majorFouls: Double?
    let minorFouls: Double?
    let finalScore: Double?
}

enum MatchOutcome: String, Equatable {
    case win
    case loss
    case tie
    case unavailable
}

struct MatchRecord: Identifiable, Equatable, Hashable {
    let id: String
    let series: Double?
    let matchNumber: Double?
    let redTeams: [Int]
    let blueTeams: [Int]
    let redScore: ScoreBreakdown
    let blueScore: ScoreBreakdown

    var displayTitle: String {
        if series == 0 {
            return "Qualification - \(Self.displayNumber(matchNumber))"
        }
        if let series {
            return "Playoff - \(Self.displayNumber(series))"
        }
        return "Match - \(Self.displayNumber(matchNumber))"
    }

    func alliance(for teamNumber: Int) -> AllianceColor? {
        if redTeams.contains(teamNumber) { return .red }
        if blueTeams.contains(teamNumber) { return .blue }
        return nil
    }

    func outcome(for teamNumber: Int) -> MatchOutcome {
        guard let alliance = alliance(for: teamNumber),
              let redFinal = redScore.finalScore,
              let blueFinal = blueScore.finalScore else {
            return .unavailable
        }
        if redFinal == blueFinal { return .tie }
        let redWon = redFinal > blueFinal
        return (alliance == .red) == redWon ? .win : .loss
    }

    func nonPenaltyScore(for alliance: AllianceColor) -> Double? {
        switch alliance {
        case .red:
            guard let final = redScore.finalScore else { return nil }
            let penalty = redScore.foulScore ?? blueScore.foulCommitted
            return penalty.map { final - $0 }
        case .blue:
            guard let final = blueScore.finalScore else { return nil }
            let penalty = blueScore.foulScore ?? redScore.foulCommitted
            return penalty.map { final - $0 }
        }
    }

    private static func displayNumber(_ number: Double?) -> String {
        guard let number else { return "-" }
        if number.rounded() == number {
            return Int(number).formatted()
        }
        return number.formatted(.number.precision(.fractionLength(1)))
    }
}

enum HighlightMetric: String, CaseIterable, Identifiable {
    case final
    case nonPenalty
    case auto
    case teleop

    var id: String { rawValue }
}

struct HighlightEntry: Identifiable, Equatable {
    let match: MatchRecord
    let alliance: AllianceColor
    let score: Double

    var id: String { "\(match.id)-\(alliance.rawValue)" }

    var teams: [Int] {
        alliance == .red ? match.redTeams : match.blueTeams
    }
}

struct EventHighlight: Identifiable, Equatable {
    let metric: HighlightMetric
    let score: Double?
    let entries: [HighlightEntry]

    var id: HighlightMetric { metric }
}

struct EventData: Equatable {
    let eventCode: String
    let eventName: String
    let mode: EventMode
    let standings: [TeamStanding]
    let matches: [MatchRecord]
    let matchesByTeam: [Int: [MatchRecord]]
    let highlights: [EventHighlight]
    let statusMessage: String

    init(
        eventCode: String,
        eventName: String,
        mode: EventMode,
        standings: [TeamStanding],
        matches: [MatchRecord],
        statusMessage: String
    ) {
        self.eventCode = eventCode
        self.eventName = eventName
        self.mode = mode
        self.standings = standings
        self.matches = matches
        var matchIndex: [Int: [MatchRecord]] = [:]
        for match in matches {
            for teamNumber in match.redTeams + match.blueTeams {
                matchIndex[teamNumber, default: []].append(match)
            }
        }
        matchesByTeam = matchIndex
        highlights = Self.makeHighlights(from: matches)
        self.statusMessage = statusMessage
    }

    private static func makeHighlights(from matches: [MatchRecord]) -> [EventHighlight] {
        HighlightMetric.allCases.map { metric in
            var highest: Double?
            var entries: [HighlightEntry] = []

            for match in matches {
                for alliance in [AllianceColor.red, .blue] {
                    let breakdown = alliance == .red ? match.redScore : match.blueScore
                    let score: Double?
                    switch metric {
                    case .final:
                        score = breakdown.finalScore
                    case .nonPenalty:
                        score = match.nonPenaltyScore(for: alliance)
                    case .auto:
                        score = breakdown.autoScore
                    case .teleop:
                        score = breakdown.teleopScore
                    }

                    guard let score else { continue }
                    let entry = HighlightEntry(match: match, alliance: alliance, score: score)
                    if highest == nil || score > highest! {
                        highest = score
                        entries = [entry]
                    } else if score == highest {
                        entries.append(entry)
                    }
                }
            }

            return EventHighlight(metric: metric, score: highest, entries: entries)
        }
    }
}

enum TagColor: String, CaseIterable, Codable, Identifiable {
    case blue
    case green
    case red
    case yellow
    case purple
    case pink
    case orange
    case gray

    var id: String { rawValue }
}

struct TeamTag: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let text: String
    let color: TagColor

    init(id: UUID = UUID(), text: String, color: TagColor) {
        self.id = id
        self.text = text
        self.color = color
    }
}

struct StoredTeamTags: Identifiable, Codable, Equatable {
    let eventCode: String
    let teamNumber: Int
    var tags: [TeamTag]

    var id: String { "\(eventCode)-\(teamNumber)" }
}

struct TeamSelection: Identifiable, Equatable {
    let eventCode: String
    let teamNumber: Int

    var id: String { "\(eventCode)-\(teamNumber)" }
}
