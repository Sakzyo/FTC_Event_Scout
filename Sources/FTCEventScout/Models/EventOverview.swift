import Foundation

/// One key figure in the event header, shown as an icon row beside the event details.
struct EventOverviewStat: Identifiable, Equatable {
    enum Kind: String {
        case teams
        case matches
        case topNonPenaltyOPR
        case highScore
        case rookies
        case peakOPR
        case averagePeakOPR
    }

    let kind: Kind
    /// Display label in its final case, for example "Top npOPR".
    let label: String
    let accessibilityLabel: String
    let value: Double?
    let fractionLength: ClosedRange<Int>
    let detail: String?
    let accessibilityDetail: String?

    var id: Kind { kind }

    /// SF Symbol shown before the figure.
    var symbolName: String {
        switch kind {
        case .teams: "person.3.fill"
        case .matches: "bolt.fill"
        case .topNonPenaltyOPR: "chart.bar.fill"
        case .highScore: "trophy.fill"
        case .rookies: "leaf.fill"
        case .peakOPR: "chart.line.uptrend.xyaxis"
        case .averagePeakOPR: "chart.bar.fill"
        }
    }
}

extension EventData {
    /// Four headline figures: live events summarize results, previews summarize team history.
    var overviewStats: [EventOverviewStat] {
        switch mode {
        case .live:
            [teamsStat, matchesStat, topNonPenaltyOPRStat, highScoreStat]
        case .preview:
            [teamsStat, rookiesStat, peakOPRStat, averagePeakOPRStat]
        }
    }

    private var teamsStat: EventOverviewStat {
        EventOverviewStat(
            kind: .teams,
            label: "Teams",
            accessibilityLabel: "Teams",
            value: Double(standings.count),
            fractionLength: 0 ... 0,
            detail: nil,
            accessibilityDetail: nil
        )
    }

    private var matchesStat: EventOverviewStat {
        let played = matches.filter {
            $0.redScore.finalScore != nil && $0.blueScore.finalScore != nil
        }.count
        let hasUnplayed = played < matches.count
        return EventOverviewStat(
            kind: .matches,
            label: "Matches",
            accessibilityLabel: "Matches",
            value: Double(matches.count),
            fractionLength: 0 ... 0,
            detail: hasUnplayed ? "\(played) played" : nil,
            accessibilityDetail: hasUnplayed ? "\(played) played" : nil
        )
    }

    private var topNonPenaltyOPRStat: EventOverviewStat {
        let leader = oprChartSeries.first { $0.metric == .nonPenalty }?.leader
        return EventOverviewStat(
            kind: .topNonPenaltyOPR,
            label: "Top npOPR",
            accessibilityLabel: "Top non-penalty OPR",
            value: leader?.value,
            fractionLength: 1 ... 1,
            detail: leader.map { "#\($0.teamLabel)" },
            accessibilityDetail: leader.map { "Team \($0.teamLabel)" }
        )
    }

    private var highScoreStat: EventOverviewStat {
        let highlight = highlights.first { $0.metric == .final }
        let entry = highlight?.entries.first
        return EventOverviewStat(
            kind: .highScore,
            label: "High score",
            accessibilityLabel: "High score",
            value: highlight?.score,
            fractionLength: 0 ... 1,
            detail: entry.map { "\($0.match.compactTitle) · \($0.alliance == .red ? "Red" : "Blue")" },
            accessibilityDetail: entry.map { "\($0.match.displayTitle), \($0.alliance.rawValue) alliance" }
        )
    }

    private var rookiesStat: EventOverviewStat {
        EventOverviewStat(
            kind: .rookies,
            label: "Rookies",
            accessibilityLabel: "Rookie teams",
            value: Double(standings.filter { $0.rookieYear == season }.count),
            fractionLength: 0 ... 0,
            detail: nil,
            accessibilityDetail: nil
        )
    }

    private var peakOPRStat: EventOverviewStat {
        let leader = standings
            .filter { $0.highestOPR?.isFinite == true }
            .max { lhs, rhs in
                if lhs.highestOPR == rhs.highestOPR {
                    return lhs.teamNumber > rhs.teamNumber
                }
                return (lhs.highestOPR ?? 0) < (rhs.highestOPR ?? 0)
            }
        let detail = leader.map { standing in
            ["#\(standing.teamNumber.teamNumberText)", standing.bestSeason.map(String.init)]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
        return EventOverviewStat(
            kind: .peakOPR,
            label: "Peak OPR",
            accessibilityLabel: "Highest historical OPR",
            value: leader?.highestOPR,
            fractionLength: 1 ... 1,
            detail: detail,
            accessibilityDetail: leader.map { "Team \($0.teamNumber.teamNumberText)" }
        )
    }

    private var averagePeakOPRStat: EventOverviewStat {
        let values = standings.compactMap(\.highestOPR).filter(\.isFinite)
        let average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        return EventOverviewStat(
            kind: .averagePeakOPR,
            label: "Avg peak OPR",
            accessibilityLabel: "Average highest historical OPR",
            value: average,
            fractionLength: 1 ... 1,
            detail: nil,
            accessibilityDetail: nil
        )
    }
}
