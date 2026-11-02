import Foundation

/// Reads and writes manual-event CSVs. The app's own format round-trips every field; the
/// `Match Details.csv` files FTC Event Scout generates from FIRST Events import as totals.
enum ManualEventCSV {
    struct ImportIssue: Equatable, Identifiable {
        let line: Int
        let message: String

        var id: String { "\(line)-\(message)" }
    }

    struct ImportResult: Equatable {
        var matches: [ManualMatch]
        var issues: [ImportIssue]
        var usedMatchDetailsFormat: Bool
    }

    // MARK: Export

    static func export(_ event: ManualEvent) -> String {
        let headers = headers(season: event.season)
        let rows = event.sortedMatches.map { match in
            headers.map { value(for: $0, match: match, season: event.season) }
        }
        return encode([headers] + rows)
    }

    static func template(season: Int) -> String {
        encode([headers(season: season)])
    }

    static func headers(season: Int) -> [String] {
        var headers = ["Level", "Match", "Game", "Red1", "Red2", "Blue1", "Blue2", "Scored"]
        let detailed = season == BiobuzzScoring.season
        if detailed {
            headers.append("Entry")
        }
        for prefix in ["Red", "Blue"] {
            if detailed {
                headers += BiobuzzColumn.allCases.map { "\(prefix) \($0.title)" }
            }
            headers += TotalsColumn.allCases.map { "\(prefix) \($0.title)" }
            if detailed {
                headers.append("\(prefix) Overrides")
            }
        }
        if detailed {
            headers += BiobuzzFlower.allCases.map(\.title)
        }
        return headers
    }

    // MARK: Import

    static func importMatches(
        from data: Data,
        season: Int,
        existing: [ManualMatch] = []
    ) throws -> ImportResult {
        let rows = try CSVParser.rows(from: data)
        guard let first = rows.first else {
            return ImportResult(matches: [], issues: [], usedMatchDetailsFormat: false)
        }

        let candidates: [(line: Int, result: Result<ManualMatch, RowError>)]
        let usedMatchDetailsFormat = first.keys.contains("Red1 Team Number")
        if usedMatchDetailsFormat {
            let records = try EventService().parseMatches(data: data, season: season)
            candidates = records.enumerated().map { index, record in
                (index + 2, .success(manualMatch(from: record, season: season)))
            }
        } else {
            candidates = rows.enumerated().map { index, row in
                (index + 2, Result { try manualMatch(from: row, season: season) }
                    .mapError { $0 as? RowError ?? RowError($0.localizedDescription) })
            }
        }

        var matches: [ManualMatch] = []
        var issues: [ImportIssue] = []
        var usedKeys = Set(existing.map(\.sortKey))
        for candidate in candidates {
            switch candidate.result {
            case .failure(let error):
                issues.append(ImportIssue(line: candidate.line, message: error.message))
            case .success(let match):
                let teams = [match.red1, match.red2, match.blue1, match.blue2]
                let present = teams.compactMap { $0 }
                if present.count < 4 {
                    issues.append(ImportIssue(line: candidate.line, message: "\(match.title) needs all four team numbers."))
                } else if Set(present).count != present.count || present.contains(where: { $0 <= 0 }) {
                    issues.append(ImportIssue(line: candidate.line, message: "\(match.title) has a repeated or invalid team number."))
                } else if !usedKeys.insert(match.sortKey).inserted {
                    issues.append(ImportIssue(line: candidate.line, message: "\(match.title) already exists, so this row was skipped."))
                } else {
                    matches.append(match)
                }
            }
        }
        return ImportResult(matches: matches, issues: issues, usedMatchDetailsFormat: usedMatchDetailsFormat)
    }

    // MARK: - Columns

    private enum BiobuzzColumn: CaseIterable {
        case autoHiveTips
        case autoRobot1Leave
        case autoRobot2Leave
        case autoRobot1Park
        case autoRobot2Park
        case teleopHiveTips
        case hivePollenNectar
        case gardenPollenNectar
        case teleopRobot1Park
        case teleopRobot2Park
        case minorFouls
        case majorFouls

        var title: String {
            switch self {
            case .autoHiveTips: "Auto Hive Tips"
            case .autoRobot1Leave: "Auto Robot1 Leave"
            case .autoRobot2Leave: "Auto Robot2 Leave"
            case .autoRobot1Park: "Auto Robot1 Park"
            case .autoRobot2Park: "Auto Robot2 Park"
            case .teleopHiveTips: "Teleop Hive Tips"
            case .hivePollenNectar: "Hive Pollen Nectar"
            case .gardenPollenNectar: "Garden Pollen Nectar"
            case .teleopRobot1Park: "Teleop Robot1 Park"
            case .teleopRobot2Park: "Teleop Robot2 Park"
            case .minorFouls: "Minor Fouls"
            case .majorFouls: "Major Fouls"
            }
        }

        var integerKeyPath: WritableKeyPath<BiobuzzAllianceInput, Int>? {
            switch self {
            case .autoHiveTips: \.autoHiveTips
            case .teleopHiveTips: \.teleopHiveTips
            case .hivePollenNectar: \.teleopHivePollenNectar
            case .gardenPollenNectar: \.teleopGardenPollenNectar
            case .minorFouls: \.minorFouls
            case .majorFouls: \.majorFouls
            default: nil
            }
        }

        var booleanKeyPath: WritableKeyPath<BiobuzzAllianceInput, Bool>? {
            switch self {
            case .autoRobot1Leave: \.autoRobot1Leave
            case .autoRobot2Leave: \.autoRobot2Leave
            case .autoRobot1Park: \.autoRobot1Park
            case .autoRobot2Park: \.autoRobot2Park
            case .teleopRobot1Park: \.teleopRobot1Park
            case .teleopRobot2Park: \.teleopRobot2Park
            default: nil
            }
        }
    }

    private enum TotalsColumn: CaseIterable {
        case auto
        case driverControlled
        case endgame
        case penaltyReceived
        case finalOverride

        var title: String {
            switch self {
            case .auto: "Auto"
            case .driverControlled: "Driver Controlled"
            case .endgame: "Endgame"
            case .penaltyReceived: "Penalty Received"
            case .finalOverride: "Final Override"
            }
        }

        var keyPath: WritableKeyPath<ManualTotals, Int?> {
            switch self {
            case .auto: \.auto
            case .driverControlled: \.driverControlled
            case .endgame: \.endgame
            case .penaltyReceived: \.penaltyReceived
            case .finalOverride: \.finalOverride
            }
        }
    }

    private static func value(for header: String, match: ManualMatch, season: Int) -> String {
        switch header {
        case "Level": return match.level.shortTitle
        case "Match": return String(match.number)
        case "Game": return String(match.game)
        case "Red1": return match.red1.map(String.init) ?? ""
        case "Red2": return match.red2.map(String.init) ?? ""
        case "Blue1": return match.blue1.map(String.init) ?? ""
        case "Blue2": return match.blue2.map(String.init) ?? ""
        case "Scored": return match.isScored ? "Y" : "N"
        case "Entry": return match.entryStyle == .detailed ? "Detailed" : "Totals"
        default: break
        }
        if let flower = BiobuzzFlower.allCases.first(where: { $0.title == header }) {
            return match.flowers[flower].map(\.rawValue).joined(separator: "|")
        }
        for alliance in [AllianceColor.red, .blue] {
            let prefix = alliance == .red ? "Red " : "Blue "
            guard header.hasPrefix(prefix) else { continue }
            let name = String(header.dropFirst(prefix.count))
            let input = match.input(for: alliance)
            if name == "Overrides" {
                return input.biobuzz.overrides
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ";")
            }
            if let column = BiobuzzColumn.allCases.first(where: { $0.title == name }) {
                if let keyPath = column.integerKeyPath {
                    return String(input.biobuzz[keyPath: keyPath])
                }
                if let keyPath = column.booleanKeyPath {
                    return input.biobuzz[keyPath: keyPath] ? "Y" : "N"
                }
            }
            if let column = TotalsColumn.allCases.first(where: { $0.title == name }) {
                return input.totals[keyPath: column.keyPath].map(String.init) ?? ""
            }
        }
        return ""
    }

    // MARK: - Row parsing

    private struct RowError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private static func manualMatch(from row: [String: String], season: Int) throws -> ManualMatch {
        func text(_ key: String) -> String {
            row[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let level: ManualMatchLevel
        switch text("Level").lowercased() {
        case "", "q", "qual", "quals", "qualification": level = .qualification
        case "p", "playoff", "playoffs", "e", "elim", "elimination": level = .playoff
        default: throw RowError("Level must be Q or P, not “\(text("Level"))”.")
        }
        guard let number = try integer(text("Match"), column: "Match"), number > 0 else {
            throw RowError("Match must be a positive number.")
        }
        let game = try integer(text("Game"), column: "Game") ?? 1

        var match = ManualMatch(
            level: level,
            number: number,
            game: max(game, 1),
            red1: try integer(text("Red1"), column: "Red1"),
            red2: try integer(text("Red2"), column: "Red2"),
            blue1: try integer(text("Blue1"), column: "Blue1"),
            blue2: try integer(text("Blue2"), column: "Blue2")
        )

        let detailed = season == BiobuzzScoring.season
        switch text("Entry").lowercased() {
        case "": match.entryStyle = detailed && hasDetailedValues(row) ? .detailed : .totals
        case "detailed", "detail", "d": match.entryStyle = detailed ? .detailed : .totals
        case "totals", "total", "t", "totals only": match.entryStyle = .totals
        default: throw RowError("Entry must be Detailed or Totals.")
        }

        var hasScoreValues = false
        for alliance in [AllianceColor.red, .blue] {
            let prefix = alliance == .red ? "Red" : "Blue"
            var input = ManualAllianceEntry()
            for column in TotalsColumn.allCases {
                let raw = text("\(prefix) \(column.title)")
                hasScoreValues = hasScoreValues || !raw.isEmpty
                input.totals[keyPath: column.keyPath] = try integer(raw, column: "\(prefix) \(column.title)")
            }
            if detailed {
                for column in BiobuzzColumn.allCases {
                    let name = "\(prefix) \(column.title)"
                    let raw = text(name)
                    hasScoreValues = hasScoreValues || !raw.isEmpty
                    if let keyPath = column.integerKeyPath {
                        input.biobuzz[keyPath: keyPath] = try integer(raw, column: name) ?? 0
                    } else if let keyPath = column.booleanKeyPath {
                        input.biobuzz[keyPath: keyPath] = try boolean(raw, column: name)
                    }
                }
                input.biobuzz.overrides = try overrides(text("\(prefix) Overrides"), column: "\(prefix) Overrides")
            }
            if alliance == .red { match.red = input } else { match.blue = input }
        }
        if detailed {
            for flower in BiobuzzFlower.allCases {
                let raw = text(flower.title)
                hasScoreValues = hasScoreValues || !raw.isEmpty
                match.flowers[flower] = try flowerElements(raw, column: flower.title)
            }
        }

        let scored = text("Scored")
        match.isScored = scored.isEmpty ? hasScoreValues : try boolean(scored, column: "Scored")
        return match
    }

    private static func hasDetailedValues(_ row: [String: String]) -> Bool {
        let names = ["Red", "Blue"].flatMap { prefix in
            BiobuzzColumn.allCases.map { "\(prefix) \($0.title)" }
        } + BiobuzzFlower.allCases.map(\.title)
        return names.contains { !(row[$0] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// FIRST Events match totals become a Totals Only match. Teleop there includes endgame.
    private static func manualMatch(from record: MatchRecord, season: Int) -> ManualMatch {
        func totals(_ score: ScoreBreakdown, opponent: ScoreBreakdown) -> ManualTotals {
            func int(_ value: Double?) -> Int? { value.map { Int($0.rounded()) } }
            var totals = ManualTotals(
                auto: int(score.autoScore),
                driverControlled: int(score.teleopScore.map { $0 - (score.endgameScore ?? 0) }),
                endgame: int(score.endgameScore),
                penaltyReceived: int(score.foulScore ?? opponent.foulCommitted)
            )
            if let final = int(score.finalScore), final != totals.calculatedFinal {
                totals.finalOverride = final
            }
            return totals
        }

        let isPlayoff = (record.series ?? 0) > 0
        var match = ManualMatch(
            level: isPlayoff ? .playoff : .qualification,
            number: Int(isPlayoff ? record.series ?? 1 : record.matchNumber ?? 1),
            game: isPlayoff ? max(Int(record.matchNumber ?? 1), 1) : 1,
            red1: record.redTeams.first,
            red2: record.redTeams.dropFirst().first,
            blue1: record.blueTeams.first,
            blue2: record.blueTeams.dropFirst().first,
            isScored: record.redScore.finalScore != nil && record.blueScore.finalScore != nil,
            entryStyle: .totals
        )
        match.red.totals = totals(record.redScore, opponent: record.blueScore)
        match.blue.totals = totals(record.blueScore, opponent: record.redScore)
        return match
    }

    private static func integer(_ text: String, column: String) throws -> Int? {
        guard !text.isEmpty else { return nil }
        guard let value = Double(text), value.isFinite, value.rounded() == value else {
            throw RowError("\(column) must be a whole number, not “\(text)”.")
        }
        guard value >= 0 else {
            throw RowError("\(column) cannot be negative.")
        }
        return Int(value)
    }

    private static func boolean(_ text: String, column: String) throws -> Bool {
        switch text.lowercased() {
        case "", "n", "no", "false", "0": return false
        case "y", "yes", "true", "1", "x": return true
        default: throw RowError("\(column) must be Y or N, not “\(text)”.")
        }
    }

    private static func flowerElements(_ text: String, column: String) throws -> [BiobuzzFlowerElement] {
        guard !text.isEmpty else { return [] }
        return try text.split(separator: "|").map { token in
            switch token.trimmingCharacters(in: .whitespaces).uppercased() {
            case "POLLEN", "P": return .pollen
            case "RED_NECTAR", "RED NECTAR", "R": return .redNectar
            case "BLUE_NECTAR", "BLUE NECTAR", "B": return .blueNectar
            default: throw RowError("\(column) has an unknown element “\(token)”. Use POLLEN, RED_NECTAR, or BLUE_NECTAR.")
            }
        }
    }

    private static func overrides(_ text: String, column: String) throws -> [String: Int] {
        var overrides: [String: Int] = [:]
        for entry in text.split(separator: ";") where !entry.trimmingCharacters(in: .whitespaces).isEmpty {
            let parts = entry.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2,
                  BiobuzzPointField(rawValue: parts[0]) != nil,
                  let value = Int(parts[1]) else {
                throw RowError("\(column) has an unreadable entry “\(entry)”.")
            }
            overrides[parts[0]] = value
        }
        return overrides
    }

    // MARK: - Writing

    private static func encode(_ rows: [[String]]) -> String {
        rows.map { row in row.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
