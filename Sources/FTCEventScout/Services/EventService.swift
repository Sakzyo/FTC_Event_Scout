import Foundation

struct EventService {
    func load(eventCode: String, season: Int, context: BackendContext) async throws -> EventData {
        let endpoint = context.baseURL.appendingPathComponent("api/generate-opr")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GenerateRequest(
            eventCode: eventCode,
            season: season
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EventServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data).error)
                ?? "The local data service returned HTTP \(httpResponse.statusCode)."
            throw EventServiceError.server(message)
        }

        let payload = try JSONDecoder().decode(GenerateResponse.self, from: data)
        if payload.mode == "preview" {
            return previewData(eventCode: eventCode, season: season, payload: payload)
        }
        return try liveData(
            eventCode: eventCode,
            season: season,
            payload: payload,
            context: context
        )
    }

    private func previewData(
        eventCode: String,
        season: Int,
        payload: GenerateResponse
    ) -> EventData {
        let previewTeams = payload.teams ?? []
        let standings = previewTeams.enumerated().compactMap { index, team -> TeamStanding? in
            guard let teamNumber = team.teamNumber else { return nil }
            return TeamStanding(
                teamNumber: teamNumber,
                storedRank: index + 1,
                teamName: team.teamName ?? "",
                totalOPR: nil,
                nonPenaltyOPR: nil,
                autoOPR: nil,
                teleopOPR: nil,
                endgameOPR: nil,
                highestOPR: team.highestOPR,
                bestSeason: team.highestOPRSeason,
                rookieYear: team.rookieYear,
                perSeason: team.perSeason ?? [:]
            )
        }

        let message = payload.message
            ?? "This event has not started. Showing historical OPR for registered teams."
        return EventData(
            eventCode: payload.eventCode ?? eventCode,
            eventName: payload.eventName ?? "",
            season: payload.season ?? season,
            mode: .preview,
            standings: standings,
            matches: [],
            statusMessage: message
        )
    }

    private func liveData(
        eventCode: String,
        season: Int,
        payload: GenerateResponse,
        context: BackendContext
    ) throws -> EventData {
        let safeCode = payload.eventCode ?? eventCode
        let safeSeason = payload.season ?? season
        let rankingsURL = context.dataDirectory
            .appendingPathComponent("events_teams_opr", isDirectory: true)
            .appendingPathComponent(String(safeSeason), isDirectory: true)
            .appendingPathComponent("\(safeCode) OPR.csv")
        let matchesURL = context.dataDirectory
            .appendingPathComponent("event_results", isDirectory: true)
            .appendingPathComponent(String(safeSeason), isDirectory: true)
            .appendingPathComponent("\(safeCode) Match Details.csv")

        let standings = try parseStandings(at: rankingsURL)
        let matches = try parseMatches(at: matchesURL, season: safeSeason)
        guard !standings.isEmpty else {
            throw EventServiceError.emptyRankings(safeCode)
        }

        return EventData(
            eventCode: safeCode,
            eventName: payload.eventName ?? "",
            season: safeSeason,
            mode: .live,
            standings: standings,
            matches: matches,
            statusMessage: "Loaded \(standings.count) teams and \(matches.count) matches."
        )
    }

    private func parseStandings(at url: URL) throws -> [TeamStanding] {
        let rows = try CSVParser.rows(from: Data(contentsOf: url))
        return rows.compactMap { row in
            guard let teamNumber = integer(row, keys: ["Team Number"]) else { return nil }
            return TeamStanding(
                teamNumber: teamNumber,
                storedRank: integer(row, keys: ["Rank"]) ?? 0,
                teamName: "",
                totalOPR: number(row, keys: ["OPR"]),
                nonPenaltyOPR: number(row, keys: ["npOPR", "OPR No Penalty Scored"]),
                autoOPR: number(row, keys: ["Auto OPR", "OPR Auto"]),
                teleopOPR: number(row, keys: ["Teleop OPR", "OPR Teleop Only"]),
                endgameOPR: number(row, keys: ["Endgame OPR", "OPR Endgame"]),
                highestOPR: nil,
                bestSeason: nil,
                rookieYear: nil,
                perSeason: [:]
            )
        }
    }

    private func parseMatches(at url: URL, season: Int) throws -> [MatchRecord] {
        let rows = try CSVParser.rows(from: Data(contentsOf: url))
        return rows.enumerated().map { index, row in
            let series = number(row, keys: ["Series"])
            let matchNumber = number(row, keys: ["Match Number"])
            let redTeams = teamNumbers(row, prefix: "Red")
            let blueTeams = teamNumbers(row, prefix: "Blue")
            let identity = [
                series.map { String($0) } ?? "-",
                matchNumber.map { String($0) } ?? "-",
                redTeams.map(String.init).joined(separator: "-"),
                blueTeams.map(String.init).joined(separator: "-"),
                String(index),
            ].joined(separator: ":")
            return MatchRecord(
                id: identity,
                series: series,
                matchNumber: matchNumber,
                redTeams: redTeams,
                blueTeams: blueTeams,
                redScore: scoreBreakdown(row, prefix: "Red", season: season),
                blueScore: scoreBreakdown(row, prefix: "Blue", season: season)
            )
        }
        .sorted { lhs, rhs in
            let left = (lhs.series ?? 0, lhs.matchNumber ?? 0)
            let right = (rhs.series ?? 0, rhs.matchNumber ?? 0)
            return left < right
        }
    }

    private func teamNumbers(_ row: [String: String], prefix: String) -> [Int] {
        [1, 2].compactMap { integer(row, keys: ["\(prefix)\($0) Team Number"]) }
    }

    private func scoreBreakdown(
        _ row: [String: String],
        prefix: String,
        season: Int
    ) -> ScoreBreakdown {
        func value(_ name: String) -> Double? {
            number(row, keys: ["\(prefix) \(name)"])
        }

        let autoScore = value("Auto Score")
        let teleopScore = value("Teleop Score")
        let endgameScore = value("Endgame Score")
        let foulScore = value("Foul Score")
        let finalScore = value("Final Score")
        let details = decodedBreakdownDetails(row, prefix: prefix)
        return ScoreBreakdown(
            autoScore: autoScore,
            teleopScore: teleopScore,
            endgameScore: endgameScore,
            foulScore: foulScore,
            foulCommitted: value("Foul Committed"),
            majorFouls: value("Major Fouls"),
            minorFouls: value("Minor Fouls"),
            finalScore: finalScore,
            details: details.isEmpty
                ? genericBreakdownDetails(
                    season: season,
                    autoScore: autoScore,
                    teleopScore: teleopScore,
                    endgameScore: endgameScore,
                    foulScore: foulScore,
                    finalScore: finalScore
                )
                : details
        )
    }

    private func decodedBreakdownDetails(
        _ row: [String: String],
        prefix: String
    ) -> [ScoreBreakdownDetail] {
        let raw = row["\(prefix) Score Breakdown"] ?? ""
        guard let data = raw.data(using: .utf8), !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([ScoreBreakdownDetail].self, from: data)) ?? []
    }

    private func genericBreakdownDetails(
        season: Int,
        autoScore: Double?,
        teleopScore: Double?,
        endgameScore: Double?,
        foulScore: Double?,
        finalScore: Double?
    ) -> [ScoreBreakdownDetail] {
        func detail(_ id: String, _ label: String, _ value: Double?) -> ScoreBreakdownDetail? {
            guard let value else { return nil }
            let display = value.rounded() == value
                ? String(Int(value))
                : value.formatted(.number.precision(.fractionLength(2)))
            return ScoreBreakdownDetail(
                id: id,
                label: label,
                value: display,
                indent: 0,
                emphasized: true
            )
        }

        let teleopLabel = season <= 2023 ? "Driver Controlled" : "Teleop"
        return [
            detail("auto", "Autonomous", autoScore),
            detail("teleop", teleopLabel, teleopScore),
            detail("endgame", "End Game", endgameScore),
            detail("penalty", "Penalty Points Awarded", foulScore),
            detail("final", "Final Score", finalScore),
        ].compactMap { $0 }
    }

    private func number(_ row: [String: String], keys: [String]) -> Double? {
        for key in keys {
            let text = row[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let value = Double(text) { return value }
        }
        return nil
    }

    private func integer(_ row: [String: String], keys: [String]) -> Int? {
        number(row, keys: keys).map { Int($0) }
    }
}

private struct GenerateRequest: Encodable {
    let eventCode: String
    let season: Int
}

private struct GenerateResponse: Decodable {
    let mode: String?
    let message: String?
    let eventCode: String?
    let eventName: String?
    let season: Int?
    let teams: [PreviewTeam]?
}

private struct PreviewTeam: Decodable {
    let teamNumber: Int?
    let teamName: String?
    let rookieYear: Int?
    let highestOPR: Double?
    let highestOPRSeason: Int?
    let perSeason: [String: HistoricalSeasonOPR]?

    private enum CodingKeys: String, CodingKey {
        case teamNumber
        case teamName
        case rookieYear
        case highestOPR = "highestOpr"
        case highestOPRSeason = "highestOprSeason"
        case perSeason
    }
}

private struct APIErrorResponse: Decodable {
    let error: String
}

enum EventServiceError: LocalizedError {
    case invalidResponse
    case server(String)
    case emptyRankings(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The local data service returned an invalid response."
        case .server(let message):
            message
        case .emptyRankings(let eventCode):
            "The generated rankings for \(eventCode) are empty."
        }
    }
}
