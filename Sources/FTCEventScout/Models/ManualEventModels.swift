import Foundation

/// A user-entered event: matches typed into the app or imported from CSV instead of fetched
/// from FIRST Events. It is stored on the Mac and converted into `EventData` for display.
struct ManualEvent: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let season: Int
    let createdAt: Date
    var updatedAt: Date
    var matches: [ManualMatch]

    init(
        id: UUID = UUID(),
        name: String,
        season: Int,
        createdAt: Date = Date(),
        matches: [ManualMatch] = []
    ) {
        self.id = id
        self.name = name
        self.season = season
        self.createdAt = createdAt
        updatedAt = createdAt
        self.matches = matches
    }

    /// A stable code used wherever the app keys data by event, such as team tags.
    /// The prefix keeps it from colliding with a real FIRST event code.
    var eventCode: String {
        "MANUAL-\(id.uuidString.prefix(8))"
    }

    /// BIOBUZZ is the only season with a full, calculated score form; the rest enter totals.
    var supportsDetailedEntry: Bool {
        season == BiobuzzScoring.season
    }

    var sortedMatches: [ManualMatch] {
        matches.sorted { $0.sortKey < $1.sortKey }
    }

    /// The next free match after `match` at the same level, for fast sequential entry.
    func nextMatch(after match: ManualMatch?) -> ManualMatch {
        let level = match?.level ?? .qualification
        let used = matches.filter { $0.level == level }.map(\.number)
        let number = (used.max() ?? 0) + 1
        return ManualMatch(
            level: level,
            number: number,
            isScored: true,
            entryStyle: supportsDetailedEntry ? .detailed : .totals,
            recording: match?.recording ?? .alliance
        )
    }
}

enum ManualMatchLevel: String, Codable, CaseIterable, Identifiable {
    case qualification
    case playoff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qualification: "Qualification"
        case .playoff: "Playoff"
        }
    }

    var shortTitle: String {
        switch self {
        case .qualification: "Q"
        case .playoff: "P"
        }
    }
}

enum ManualEntryStyle: String, Codable, CaseIterable, Identifiable {
    /// Season-specific counts and robot states, with points calculated by the app.
    case detailed
    /// Period totals typed directly.
    case totals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .detailed: "Detailed"
        case .totals: "Totals Only"
        }
    }
}

/// Whether a detailed BIOBUZZ match records alliance-wide counts or each team's own work.
enum BiobuzzRecordingMode: String, Codable, CaseIterable, Identifiable {
    /// Hive tips, hive and garden counts entered for the alliance as a whole.
    case alliance
    /// Hive cycles entered for each team; every two cycles the alliance
    /// completes tip the hive once.
    case perTeam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alliance: "Alliance"
        case .perTeam: "Per Team"
        }
    }
}

struct ManualMatch: Codable, Identifiable, Equatable {
    var id: UUID
    var level: ManualMatchLevel
    /// The qualification match number, or the playoff series (bracket match) number.
    var number: Int
    /// The game within a playoff series; finals can run more than one.
    var game: Int
    var red1: Int?
    var red2: Int?
    var blue1: Int?
    var blue2: Int?
    /// Unscored matches are the schedule: they feed OPRc predictions instead of OPR.
    var isScored: Bool
    var entryStyle: ManualEntryStyle
    /// How the detailed BIOBUZZ form is recorded. Both forms are kept, like `entryStyle`.
    var recording: BiobuzzRecordingMode
    var red: ManualAllianceEntry
    var blue: ManualAllianceEntry
    /// BIOBUZZ flowers are shared field state, so they are entered once per match.
    var flowers: BiobuzzFlowers
    /// Who last changed each part of the match and when, keyed by `ManualMatchPiece.key`.
    /// Merging scouts' files uses it to keep the newest entry for each part.
    var edits: [String: ManualEdit]

    init(
        id: UUID = UUID(),
        level: ManualMatchLevel = .qualification,
        number: Int,
        game: Int = 1,
        red1: Int? = nil,
        red2: Int? = nil,
        blue1: Int? = nil,
        blue2: Int? = nil,
        isScored: Bool = false,
        entryStyle: ManualEntryStyle = .totals,
        recording: BiobuzzRecordingMode = .alliance,
        red: ManualAllianceEntry = ManualAllianceEntry(),
        blue: ManualAllianceEntry = ManualAllianceEntry(),
        flowers: BiobuzzFlowers = BiobuzzFlowers(),
        edits: [String: ManualEdit] = [:]
    ) {
        self.id = id
        self.level = level
        self.number = number
        self.game = game
        self.red1 = red1
        self.red2 = red2
        self.blue1 = blue1
        self.blue2 = blue2
        self.isScored = isScored
        self.entryStyle = entryStyle
        self.recording = recording
        self.red = red
        self.blue = blue
        self.flowers = flowers
        self.edits = edits
    }

    var redTeams: [Int] { [red1, red2].compactMap { $0 } }
    var blueTeams: [Int] { [blue1, blue2].compactMap { $0 } }

    var sortKey: ManualMatchKey {
        ManualMatchKey(level: level, number: number, game: game)
    }

    var title: String {
        switch level {
        case .qualification: "Qualification \(number)"
        case .playoff: game > 1 ? "Playoff \(number)-\(game)" : "Playoff \(number)"
        }
    }

    var shortTitle: String {
        switch level {
        case .qualification: "Q\(number)"
        case .playoff: game > 1 ? "P\(number)-\(game)" : "P\(number)"
        }
    }

    func input(for alliance: AllianceColor) -> ManualAllianceEntry {
        alliance == .red ? red : blue
    }

    /// The alliance-wide BIOBUZZ counts scoring uses, derived from per-team entry when needed.
    func biobuzzInput(for alliance: AllianceColor) -> BiobuzzAllianceInput {
        input(for: alliance).biobuzz.scored(as: recording)
    }

    /// Problems that keep this match out of OPR, predictions, and import.
    func validationIssues(in event: ManualEvent) -> [String] {
        var issues: [String] = []
        let teams = [red1, red2, blue1, blue2]
        if teams.contains(where: { $0 == nil }) {
            issues.append("Enter all four team numbers.")
        }
        if teams.compactMap({ $0 }).contains(where: { $0 <= 0 }) {
            issues.append("Team numbers must be positive.")
        }
        let present = teams.compactMap { $0 }
        if Set(present).count != present.count {
            issues.append("A team can appear only once in a match.")
        }
        if number <= 0 || game <= 0 {
            issues.append("Match numbers must be positive.")
        }
        if event.matches.contains(where: { $0.id != id && $0.sortKey == sortKey }) {
            issues.append("\(title) already exists.")
        }
        return issues
    }
}

extension ManualMatch {
    /// Events saved before per-team recording have no `recording` key, and events saved
    /// before merging have no `edits` key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        level = try container.decode(ManualMatchLevel.self, forKey: .level)
        number = try container.decode(Int.self, forKey: .number)
        game = try container.decode(Int.self, forKey: .game)
        red1 = try container.decodeIfPresent(Int.self, forKey: .red1)
        red2 = try container.decodeIfPresent(Int.self, forKey: .red2)
        blue1 = try container.decodeIfPresent(Int.self, forKey: .blue1)
        blue2 = try container.decodeIfPresent(Int.self, forKey: .blue2)
        isScored = try container.decode(Bool.self, forKey: .isScored)
        entryStyle = try container.decode(ManualEntryStyle.self, forKey: .entryStyle)
        recording = try container.decodeIfPresent(BiobuzzRecordingMode.self, forKey: .recording) ?? .alliance
        red = try container.decode(ManualAllianceEntry.self, forKey: .red)
        blue = try container.decode(ManualAllianceEntry.self, forKey: .blue)
        flowers = try container.decode(BiobuzzFlowers.self, forKey: .flowers)
        edits = try container.decodeIfPresent([String: ManualEdit].self, forKey: .edits) ?? [:]
    }
}

/// One scout's latest change to part of a match.
struct ManualEdit: Codable, Equatable {
    var at: Date
    /// The scout name set in Settings, or nil when none was set.
    var by: String?
}

struct ManualMatchKey: Hashable, Comparable {
    let level: ManualMatchLevel
    let number: Int
    let game: Int

    static func < (lhs: ManualMatchKey, rhs: ManualMatchKey) -> Bool {
        let left = (lhs.level == .qualification ? 0 : 1, lhs.number, lhs.game)
        let right = (rhs.level == .qualification ? 0 : 1, rhs.number, rhs.game)
        return left < right
    }
}

/// Both entry forms for one alliance. Keeping both means switching between Detailed and
/// Totals Only never discards what the scout typed.
struct ManualAllianceEntry: Codable, Equatable {
    var biobuzz = BiobuzzAllianceInput()
    var totals = ManualTotals()
}

/// Period totals for seasons without a detailed form, or BIOBUZZ matches entered as totals.
struct ManualTotals: Codable, Equatable {
    var auto: Int?
    /// Driver-controlled points excluding endgame.
    var driverControlled: Int?
    var endgame: Int?
    /// Penalty points the opponent's fouls gave this alliance.
    var penaltyReceived: Int?
    /// Replaces the calculated final score when set.
    var finalOverride: Int?

    var teleop: Int? {
        guard driverControlled != nil || endgame != nil else { return nil }
        return (driverControlled ?? 0) + (endgame ?? 0)
    }

    var calculatedFinal: Int? {
        let parts = [auto, driverControlled, endgame, penaltyReceived].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    var final: Int? {
        finalOverride ?? calculatedFinal
    }
}

struct BiobuzzAllianceInput: Codable, Equatable {
    var autoHiveTips = 0
    var autoRobot1Leave = false
    var autoRobot2Leave = false
    var autoRobot1Park = false
    var autoRobot2Park = false
    var teleopHiveTips = 0
    var teleopHivePollenNectar = 0
    var teleopGardenPollenNectar = 0
    var teleopRobot1Park = false
    var teleopRobot2Park = false
    /// Fouls this alliance committed; their points go to the opponent.
    var minorFouls = 0
    var majorFouls = 0
    /// Hand-corrected point subtotals keyed by `BiobuzzPointField.rawValue`.
    var overrides: [String: Int] = [:]
    /// Per-team entry for the alliance's first and second team.
    var robot1 = BiobuzzTeamInput()
    var robot2 = BiobuzzTeamInput()

    var autoHiveCycles: Int { robot1.autoHiveCycles + robot2.autoHiveCycles }
    var totalHiveCycles: Int { autoHiveCycles + robot1.teleopHiveCycles + robot2.teleopHiveCycles }

    func override(for field: BiobuzzPointField) -> Int? {
        overrides[field.rawValue]
    }

    mutating func setOverride(_ value: Int?, for field: BiobuzzPointField) {
        overrides[field.rawValue] = value
    }

    /// The alliance-wide counts for `mode`. Per-team entry has no hive tips of its own: every
    /// two cycles the alliance completes tip the hive once. Cycles carry over from auto into
    /// teleop, so an odd auto cycle pairs with the first teleop cycle for a teleop tip.
    /// Pollen and nectar left in the hive and garden, leave, park, fouls, and overrides are
    /// entered for the alliance as before.
    func scored(as mode: BiobuzzRecordingMode) -> BiobuzzAllianceInput {
        guard mode == .perTeam else { return self }
        var input = self
        let autoTips = autoHiveCycles / BiobuzzScoring.cyclesPerHiveTip
        input.autoHiveTips = autoTips
        input.teleopHiveTips = totalHiveCycles / BiobuzzScoring.cyclesPerHiveTip - autoTips
        return input
    }
}

extension BiobuzzAllianceInput {
    /// Events saved before per-team recording have no `robot1` / `robot2` keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try container.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        self.init()
        autoHiveTips = try value(.autoHiveTips, 0)
        autoRobot1Leave = try value(.autoRobot1Leave, false)
        autoRobot2Leave = try value(.autoRobot2Leave, false)
        autoRobot1Park = try value(.autoRobot1Park, false)
        autoRobot2Park = try value(.autoRobot2Park, false)
        teleopHiveTips = try value(.teleopHiveTips, 0)
        teleopHivePollenNectar = try value(.teleopHivePollenNectar, 0)
        teleopGardenPollenNectar = try value(.teleopGardenPollenNectar, 0)
        teleopRobot1Park = try value(.teleopRobot1Park, false)
        teleopRobot2Park = try value(.teleopRobot2Park, false)
        minorFouls = try value(.minorFouls, 0)
        majorFouls = try value(.majorFouls, 0)
        overrides = try value(.overrides, [:])
        robot1 = try value(.robot1, BiobuzzTeamInput())
        robot2 = try value(.robot2, BiobuzzTeamInput())
    }
}

/// One team's share of an alliance's BIOBUZZ scoring in per-team entry.
struct BiobuzzTeamInput: Codable, Equatable {
    var autoHiveCycles = 0
    var teleopHiveCycles = 0
}

/// Calculated BIOBUZZ subtotals a scout may override.
enum BiobuzzPointField: String, CaseIterable, Identifiable, Codable {
    case autoLeave
    case autoPark
    case autoHive
    case teleopHive
    case teleopFlower
    case teleopGarden
    case teleopPark
    case foulsCommitted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autoLeave: "Auto Leave"
        case .autoPark: "Auto Park"
        case .autoHive: "Auto Hive"
        case .teleopHive: "Teleop Hive"
        case .teleopFlower: "Flowers"
        case .teleopGarden: "Garden"
        case .teleopPark: "Teleop Park"
        case .foulsCommitted: "Fouls Committed"
        }
    }
}

enum BiobuzzFlowerElement: String, Codable, CaseIterable, Identifiable {
    case pollen = "POLLEN"
    case redNectar = "RED_NECTAR"
    case blueNectar = "BLUE_NECTAR"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pollen: "Pollen"
        case .redNectar: "Red Nectar"
        case .blueNectar: "Blue Nectar"
        }
    }

    var nectarAlliance: AllianceColor? {
        switch self {
        case .pollen: nil
        case .redNectar: .red
        case .blueNectar: .blue
        }
    }
}

enum BiobuzzFlower: String, CaseIterable, Identifiable {
    case redAlliance
    case scoring
    case blueAlliance
    case audience

    var id: String { rawValue }

    var title: String {
        switch self {
        case .redAlliance: "Red Alliance Flower"
        case .scoring: "Scoring Flower"
        case .blueAlliance: "Blue Alliance Flower"
        case .audience: "Audience Flower"
        }
    }
}

/// The contents of each flower, listed bottom to top.
struct BiobuzzFlowers: Codable, Equatable {
    var redAlliance: [BiobuzzFlowerElement] = []
    var scoring: [BiobuzzFlowerElement] = []
    var blueAlliance: [BiobuzzFlowerElement] = []
    var audience: [BiobuzzFlowerElement] = []

    subscript(flower: BiobuzzFlower) -> [BiobuzzFlowerElement] {
        get {
            switch flower {
            case .redAlliance: redAlliance
            case .scoring: scoring
            case .blueAlliance: blueAlliance
            case .audience: audience
            }
        }
        set {
            switch flower {
            case .redAlliance: redAlliance = newValue
            case .scoring: scoring = newValue
            case .blueAlliance: blueAlliance = newValue
            case .audience: audience = newValue
            }
        }
    }
}
