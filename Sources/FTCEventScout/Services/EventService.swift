import Foundation

struct EventService {
    func load(eventCode: String, context: BackendContext) async throws -> EventData {
        let endpoint = context.baseURL.appendingPathComponent("api/generate-opr")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GenerateRequest(eventCode: eventCode))

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
            return previewData(eventCode: eventCode, payload: payload)
        }
        return try liveData(eventCode: eventCode, payload: payload, context: context)
    }

    private func previewData(eventCode: String, payload: GenerateResponse) -> EventData {
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
            mode: .preview,
            standings: standings,
            matches: [],
            statusMessage: message
        )
    }

    private func liveData(
        eventCode: String,
        payload: GenerateResponse,
        context: BackendContext
    ) throws -> EventData {
        let safeCode = payload.eventCode ?? eventCode
        let rankingsURL = context.dataDirectory
            .appendingPathComponent("events_teams_opr", isDirectory: true)
            .appendingPathComponent("\(safeCode) OPR.csv")
        let matchesURL = context.dataDirectory
            .appendingPathComponent("event_results", isDirectory: true)
            .appendingPathComponent("\(safeCode) Match Details.csv")

        let standings = try parseStandings(at: rankingsURL)
        let matches = try parseMatches(at: matchesURL)
        guard !standings.isEmpty else {
            throw EventServiceError.emptyRankings(safeCode)
        }

        return EventData(
            eventCode: safeCode,
            eventName: payload.eventName ?? "",
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

    private func parseMatches(at url: URL) throws -> [MatchRecord] {
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
                redScore: scoreBreakdown(row, prefix: "Red"),
                blueScore: scoreBreakdown(row, prefix: "Blue")
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

    private func scoreBreakdown(_ row: [String: String], prefix: String) -> ScoreBreakdown {
        func value(_ name: String) -> Double? {
            number(row, keys: ["\(prefix) \(name)"])
        }
        return ScoreBreakdown(
            autoScore: value("Auto Score"),
            autoArtifactPoints: value("Auto Artifact Points"),
            autoClassifiedArtifacts: value("Auto Classified Artifacts"),
            autoOverflowArtifacts: value("Auto Overflow Artifacts"),
            autoPatternPoints: value("Auto Pattern Points"),
            autoLeavePoints: value("Auto Leave Points"),
            teleopScore: value("Teleop Score"),
            teleopArtifactPoints: value("Teleop Artifact Points"),
            teleopClassifiedArtifacts: value("Teleop Classified Artifacts"),
            teleopOverflowArtifacts: value("Teleop Overflow Artifacts"),
            teleopPatternPoints: value("Teleop Pattern Points"),
            teleopDepotPoints: value("Teleop Depot Points"),
            endgameScore: value("Endgame Score"),
            foulScore: value("Foul Score"),
            foulCommitted: value("Foul Committed"),
            majorFouls: value("Major Fouls"),
            minorFouls: value("Minor Fouls"),
            finalScore: value("Final Score")
        )
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
}

private struct GenerateResponse: Decodable {
    let mode: String?
    let message: String?
    let eventCode: String?
    let eventName: String?
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
