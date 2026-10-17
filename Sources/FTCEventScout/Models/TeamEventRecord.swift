import Foundation

/// A team's qualification win-loss-tie record at one event, matching how event rankings count play.
struct TeamEventRecord: Equatable, Hashable {
    var wins = 0
    var losses = 0
    var ties = 0

    var played: Int { wins + losses + ties }

    /// Ties count as half a win, so records with different match counts compare fairly.
    var winRate: Double? {
        guard played > 0 else { return nil }
        return (Double(wins) + Double(ties) / 2) / Double(played)
    }

    /// "W-L-T", the format FTC rankings use.
    var displayText: String { "\(wins)-\(losses)-\(ties)" }

    var accessibilityText: String {
        "\(wins) wins, \(losses) losses, \(ties) ties"
    }

    /// Counts every scored qualification match. Playoff matches (series above zero) are excluded,
    /// and matches without a series are treated as qualifications.
    static func make(from matches: [MatchRecord]) -> [Int: TeamEventRecord] {
        var records: [Int: TeamEventRecord] = [:]
        for match in matches where match.series == nil || match.series == 0 {
            for teamNumber in match.redTeams + match.blueTeams {
                switch match.outcome(for: teamNumber) {
                case .win: records[teamNumber, default: TeamEventRecord()].wins += 1
                case .loss: records[teamNumber, default: TeamEventRecord()].losses += 1
                case .tie: records[teamNumber, default: TeamEventRecord()].ties += 1
                case .unavailable: break
                }
            }
        }
        return records
    }
}

extension TeamEventRecord: Comparable {
    /// Orders by win rate, then by total wins. Use `winRate == nil` to keep unplayed teams last.
    static func < (lhs: TeamEventRecord, rhs: TeamEventRecord) -> Bool {
        let left = lhs.winRate ?? -1
        let right = rhs.winRate ?? -1
        if left != right { return left < right }
        if lhs.wins != rhs.wins { return lhs.wins < rhs.wins }
        return lhs.losses > rhs.losses
    }
}
