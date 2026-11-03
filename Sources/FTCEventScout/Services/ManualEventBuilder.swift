import Foundation

/// Converts a `ManualEvent` into the same `EventData` the FIRST Events path produces,
/// so rankings, charts, predictions, highlights, and match history work unchanged.
enum ManualEventBuilder {
    static func eventData(for event: ManualEvent) -> EventData {
        let matches = matchRecords(for: event)
        let scheduledTeams = event.matches.flatMap { $0.redTeams + $0.blueTeams }
        let standings = standings(from: matches, additionalTeams: scheduledTeams)
        let scoredCount = matches.filter { $0.redScore.finalScore != nil }.count
        return EventData(
            eventCode: event.eventCode,
            eventName: event.name,
            season: event.season,
            mode: .manual,
            standings: standings,
            matches: matches,
            statusMessage: "\(standings.count) teams, \(scoredCount) scored of \(matches.count) matches."
        )
    }

    /// Matches with at least one team per alliance; incomplete rows stay in the editor only.
    static func matchRecords(for event: ManualEvent) -> [MatchRecord] {
        event.sortedMatches.compactMap { match in
            guard !match.redTeams.isEmpty, !match.blueTeams.isEmpty else { return nil }
            let scores = scoreBreakdowns(for: match, season: event.season)
            return MatchRecord(
                id: "manual:\(match.id.uuidString)",
                series: match.level == .qualification ? 0 : Double(match.number),
                matchNumber: Double(match.level == .qualification ? match.number : match.game),
                redTeams: match.redTeams,
                blueTeams: match.blueTeams,
                redScore: scores.red,
                blueScore: scores.blue
            )
        }
    }

    static func scoreBreakdowns(
        for match: ManualMatch,
        season: Int
    ) -> (red: ScoreBreakdown, blue: ScoreBreakdown) {
        guard match.isScored else { return (unscored, unscored) }
        if match.entryStyle == .detailed && season == BiobuzzScoring.season {
            return biobuzzBreakdowns(for: match)
        }
        return (
            totalsBreakdown(match.red.totals, season: season),
            totalsBreakdown(match.blue.totals, season: season)
        )
    }

    /// OPR for every metric, mirroring `calculate_opr_from_csv.py`: npOPR removes penalty
    /// points received, and teleop OPR excludes endgame. Ranked by npOPR, highest first.
    static func standings(
        from matches: [MatchRecord],
        additionalTeams: [Int] = []
    ) -> [TeamStanding] {
        func solve(_ score: (MatchRecord, AllianceColor) -> Double?) -> [Int: Double] {
            let performances = matches.flatMap { match in
                [AllianceColor.red, .blue].compactMap { alliance -> AlliancePerformance? in
                    let teams = alliance == .red ? match.redTeams : match.blueTeams
                    guard !teams.isEmpty, let value = score(match, alliance) else { return nil }
                    return AlliancePerformance(
                        id: "\(match.id)-\(alliance.rawValue)",
                        matchID: match.id,
                        series: match.series,
                        matchNumber: match.matchNumber,
                        alliance: alliance,
                        teamNumbers: teams,
                        score: value
                    )
                }
            }
            return OPRCalculator.calculate(from: performances)?.valuesByTeam ?? [:]
        }
        func breakdown(_ match: MatchRecord, _ alliance: AllianceColor) -> ScoreBreakdown {
            alliance == .red ? match.redScore : match.blueScore
        }

        let total = solve { breakdown($0, $1).finalScore }
        let nonPenalty = solve { $0.nonPenaltyScore(for: $1) }
        let auto = solve { breakdown($0, $1).autoScore }
        let teleop = solve {
            let score = breakdown($0, $1)
            guard let teleop = score.teleopScore, let endgame = score.endgameScore else { return nil }
            return teleop - endgame
        }
        let endgame = solve { breakdown($0, $1).endgameScore }

        let teams = Set(matches.flatMap { $0.redTeams + $0.blueTeams } + additionalTeams)
            .filter { $0 > 0 }
        let ordered = teams.sorted { lhs, rhs in
            switch (nonPenalty[lhs], nonPenalty[rhs]) {
            case (.some(let left), .some(let right)) where left != right: left > right
            case (.some, .none): true
            case (.none, .some): false
            default: lhs < rhs
            }
        }
        return ordered.enumerated().map { index, team in
            TeamStanding(
                teamNumber: team,
                storedRank: index + 1,
                teamName: "",
                totalOPR: total[team],
                nonPenaltyOPR: nonPenalty[team],
                autoOPR: auto[team],
                teleopOPR: teleop[team],
                endgameOPR: endgame[team],
                seasonOPR: nil,
                rookieYear: nil
            )
        }
    }

    private static func biobuzzBreakdowns(for match: ManualMatch) -> (red: ScoreBreakdown, blue: ScoreBreakdown) {
        let red = BiobuzzScoring.score(match.red.biobuzz, alliance: .red, flowers: match.flowers)
        let blue = BiobuzzScoring.score(match.blue.biobuzz, alliance: .blue, flowers: match.flowers)

        func breakdown(
            input: BiobuzzAllianceInput,
            result: BiobuzzScoring.AllianceResult,
            opponentInput: BiobuzzAllianceInput,
            opponent: BiobuzzScoring.AllianceResult
        ) -> ScoreBreakdown {
            let penaltyAwarded = opponent.foulPointsCommitted
            let final = result.preFoulTotal + penaltyAwarded
            return ScoreBreakdown(
                autoScore: Double(result.autoPoints),
                teleopScore: Double(result.teleopPoints),
                endgameScore: Double(result.teleopParkPoints),
                foulScore: Double(penaltyAwarded),
                foulCommitted: Double(result.foulPointsCommitted),
                majorFouls: Double(input.majorFouls),
                minorFouls: Double(input.minorFouls),
                finalScore: Double(final),
                details: BiobuzzScoring.breakdownDetails(
                    input: input,
                    result: result,
                    opponentInput: opponentInput,
                    flowers: match.flowers,
                    penaltyAwarded: penaltyAwarded,
                    final: final
                )
            )
        }

        return (
            breakdown(input: match.red.biobuzz, result: red, opponentInput: match.blue.biobuzz, opponent: blue),
            breakdown(input: match.blue.biobuzz, result: blue, opponentInput: match.red.biobuzz, opponent: red)
        )
    }

    private static func totalsBreakdown(_ totals: ManualTotals, season: Int) -> ScoreBreakdown {
        let auto = totals.auto.map(Double.init)
        let teleop = totals.teleop.map(Double.init)
        let endgame = totals.endgame.map(Double.init)
        let penalty = totals.penaltyReceived.map(Double.init)
        let final = totals.final.map(Double.init)
        return ScoreBreakdown(
            autoScore: auto,
            teleopScore: teleop,
            endgameScore: endgame,
            foulScore: penalty,
            foulCommitted: nil,
            majorFouls: nil,
            minorFouls: nil,
            finalScore: final,
            details: ScoreBreakdownDetail.generic(
                season: season,
                autoScore: auto,
                teleopScore: teleop,
                endgameScore: endgame,
                foulScore: penalty,
                finalScore: final
            )
        )
    }

    private static let unscored = ScoreBreakdown(
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
