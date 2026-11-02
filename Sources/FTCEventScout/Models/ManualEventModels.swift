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
            entryStyle: supportsDetailedEntry ? .detailed : .totals
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
    var red: ManualAllianceEntry
    var blue: ManualAllianceEntry
    /// BIOBUZZ flowers are shared field state, so they are entered once per match.
    var flowers: BiobuzzFlowers

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
        red: ManualAllianceEntry = ManualAllianceEntry(),
        blue: ManualAllianceEntry = ManualAllianceEntry(),
        flowers: BiobuzzFlowers = BiobuzzFlowers()
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
        self.red = red
        self.blue = blue
        self.flowers = flowers
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

    func override(for field: BiobuzzPointField) -> Int? {
        overrides[field.rawValue]
    }

    mutating func setOverride(_ value: Int?, for field: BiobuzzPointField) {
        overrides[field.rawValue] = value
    }
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
