import Foundation

/// A part of a manual match that scouts record on their own. Merging compares each part
/// separately, so a scout watching red never overwrites one watching blue.
enum ManualMatchPiece: Hashable {
    /// Team numbers, entry style, and recording mode.
    case schedule
    /// Alliance-wide scoring: totals, hive tips, hive and garden counts, fouls, overrides.
    case alliance(AllianceColor)
    /// One team's own entries (hive cycles, leave, park), keyed by team number so they
    /// follow the team whichever slot it was typed in.
    case team(Int)
    /// BIOBUZZ flowers, shared field state.
    case flowers

    var key: String {
        switch self {
        case .schedule: "schedule"
        case .alliance(let color): color.rawValue
        case .team(let number): "team-\(number)"
        case .flowers: "flowers"
        }
    }

    var title: String {
        switch self {
        case .schedule: "Teams and entry settings"
        case .alliance(let color): color == .red ? "Red alliance scoring" : "Blue alliance scoring"
        case .team(let number): "Team \(number.teamNumberText)"
        case .flowers: "Flowers"
        }
    }
}

/// One team's own entries in a match. Alliance storage keeps them by slot (robot 1 or 2).
struct ManualTeamEntry: Equatable {
    var autoHiveCycles = 0
    var teleopHiveCycles = 0
    var autoLeave = false
    var autoPark = false
    var teleopPark = false
}

/// The team numbers and entry settings of a match.
struct ManualMatchSchedule: Equatable {
    var red1: Int?
    var red2: Int?
    var blue1: Int?
    var blue2: Int?
    var entryStyle: ManualEntryStyle
    var recording: BiobuzzRecordingMode

    var hasTeams: Bool { [red1, red2, blue1, blue2].contains { $0 != nil } }

    /// Slot order within an alliance does not matter: team entries follow team numbers.
    func hasSameTeams(as other: ManualMatchSchedule) -> Bool {
        Set([red1, red2].compactMap { $0 }) == Set([other.red1, other.red2].compactMap { $0 })
            && Set([blue1, blue2].compactMap { $0 }) == Set([other.blue1, other.blue2].compactMap { $0 })
    }

    var teamsText: String {
        func list(_ teams: [Int?]) -> String {
            teams.map { $0?.teamNumberText ?? "—" }.joined(separator: " ")
        }
        return "red \(list([red1, red2])), blue \(list([blue1, blue2]))"
    }
}

extension BiobuzzAllianceInput {
    func teamEntry(robot: Int) -> ManualTeamEntry {
        robot == 1
            ? ManualTeamEntry(
                autoHiveCycles: robot1.autoHiveCycles,
                teleopHiveCycles: robot1.teleopHiveCycles,
                autoLeave: autoRobot1Leave,
                autoPark: autoRobot1Park,
                teleopPark: teleopRobot1Park
            )
            : ManualTeamEntry(
                autoHiveCycles: robot2.autoHiveCycles,
                teleopHiveCycles: robot2.teleopHiveCycles,
                autoLeave: autoRobot2Leave,
                autoPark: autoRobot2Park,
                teleopPark: teleopRobot2Park
            )
    }

    mutating func setTeamEntry(_ entry: ManualTeamEntry, robot: Int) {
        if robot == 1 {
            robot1 = BiobuzzTeamInput(autoHiveCycles: entry.autoHiveCycles, teleopHiveCycles: entry.teleopHiveCycles)
            autoRobot1Leave = entry.autoLeave
            autoRobot1Park = entry.autoPark
            teleopRobot1Park = entry.teleopPark
        } else {
            robot2 = BiobuzzTeamInput(autoHiveCycles: entry.autoHiveCycles, teleopHiveCycles: entry.teleopHiveCycles)
            autoRobot2Leave = entry.autoLeave
            autoRobot2Park = entry.autoPark
            teleopRobot2Park = entry.teleopPark
        }
    }
}

extension ManualAllianceEntry {
    /// The alliance-wide part, with both robots' own entries cleared.
    var withoutTeamEntries: ManualAllianceEntry {
        var shared = self
        shared.biobuzz.setTeamEntry(ManualTeamEntry(), robot: 1)
        shared.biobuzz.setTeamEntry(ManualTeamEntry(), robot: 2)
        return shared
    }
}

extension ManualMatch {
    var schedule: ManualMatchSchedule {
        get {
            ManualMatchSchedule(
                red1: red1, red2: red2, blue1: blue1, blue2: blue2,
                entryStyle: entryStyle, recording: recording
            )
        }
        set {
            red1 = newValue.red1
            red2 = newValue.red2
            blue1 = newValue.blue1
            blue2 = newValue.blue2
            entryStyle = newValue.entryStyle
            recording = newValue.recording
        }
    }

    /// Every part of the match, one per team in it.
    var pieces: [ManualMatchPiece] {
        var pieces: [ManualMatchPiece] = [.schedule, .alliance(.red), .alliance(.blue), .flowers]
        var seen = Set<Int>()
        for team in redTeams + blueTeams where seen.insert(team).inserted {
            pieces.append(.team(team))
        }
        return pieces
    }

    func teamEntry(for team: Int) -> ManualTeamEntry? {
        guard let slot = slot(of: team) else { return nil }
        return input(for: slot.alliance).biobuzz.teamEntry(robot: slot.robot)
    }

    mutating func setTeamEntry(_ entry: ManualTeamEntry, for team: Int) {
        guard let slot = slot(of: team) else { return }
        if slot.alliance == .red {
            red.biobuzz.setTeamEntry(entry, robot: slot.robot)
        } else {
            blue.biobuzz.setTeamEntry(entry, robot: slot.robot)
        }
    }

    /// Replaces an alliance's shared scoring and keeps both robots' own entries.
    mutating func setAllianceScoring(from source: ManualAllianceEntry, for alliance: AllianceColor) {
        var updated = source.withoutTeamEntries
        let current = input(for: alliance).biobuzz
        updated.biobuzz.setTeamEntry(current.teamEntry(robot: 1), robot: 1)
        updated.biobuzz.setTeamEntry(current.teamEntry(robot: 2), robot: 2)
        if alliance == .red { red = updated } else { blue = updated }
    }

    /// Stamps every part that differs from `old` with `scout` and `date`. A new match
    /// (no `old`) stamps only the parts that hold something.
    func recordingEdits(since old: ManualMatch?, by scout: String?, at date: Date) -> ManualMatch {
        var updated = self
        let edit = ManualEdit(at: date, by: scout)
        for piece in pieces {
            let changed = old.map { content(of: piece) != $0.content(of: piece) } ?? !content(of: piece).isEmpty
            if changed { updated.edits[piece.key] = edit }
        }
        updated.dropStaleEdits()
        return updated
    }

    /// Whether this copy of the match holds an entry for `piece`. Something a scout typed
    /// counts even if it is all zeros; blank parts never replace another scout's entry.
    func hasEntry(for piece: ManualMatchPiece) -> Bool {
        let content = content(of: piece)
        if case .schedule = piece { return !content.isEmpty }
        return edits[piece.key] != nil || !content.isEmpty
    }

    fileprivate func content(of piece: ManualMatchPiece) -> ManualPieceContent {
        switch piece {
        case .schedule: .schedule(schedule)
        case .alliance(let color): .alliance(input(for: color).withoutTeamEntries)
        case .team(let number): .team(teamEntry(for: number) ?? ManualTeamEntry())
        case .flowers: .flowers(flowers)
        }
    }

    fileprivate mutating func dropStaleEdits() {
        let current = Set(pieces.map(\.key))
        edits = edits.filter { current.contains($0.key) }
    }

    private func slot(of team: Int) -> (alliance: AllianceColor, robot: Int)? {
        if red1 == team { return (.red, 1) }
        if red2 == team { return (.red, 2) }
        if blue1 == team { return (.blue, 1) }
        if blue2 == team { return (.blue, 2) }
        return nil
    }
}

private enum ManualPieceContent: Equatable {
    case schedule(ManualMatchSchedule)
    case alliance(ManualAllianceEntry)
    case team(ManualTeamEntry)
    case flowers(BiobuzzFlowers)

    var isEmpty: Bool {
        switch self {
        case .schedule(let schedule): !schedule.hasTeams
        case .alliance(let entry): entry == ManualAllianceEntry()
        case .team(let entry): entry == ManualTeamEntry()
        case .flowers(let flowers): flowers == BiobuzzFlowers()
        }
    }
}

/// Merges another scout's matches into an event. Matches pair up by level, number, and
/// game; within a match each part is merged on its own:
///
/// - A part only one side has an entry for is taken from that side.
/// - When both have entries that differ, the newer edit wins; ties keep this Mac's.
///   Every such case is listed in `notes`.
/// - Team entries pair up by team number, not by Robot 1 / Robot 2 slot.
/// - A match is scored if either side scored it.
///
/// Matches only this Mac has are kept; deletions do not carry over.
enum ManualEventMerge {
    struct Note: Identifiable, Equatable {
        enum Source: Equatable {
            /// The event already on this Mac.
            case existing
            /// The file being merged in.
            case incoming
        }

        let matchKey: ManualMatchKey
        let matchTitle: String
        let piece: ManualMatchPiece
        let kept: Source
        let keptEdit: ManualEdit?
        let replacedEdit: ManualEdit?
        /// Set when the head scout should check the result, such as teams that differ.
        let reviewReason: String?
        /// The file the entry came from, when several files are merged at once.
        var sourceName: String?

        var id: String { "\(sourceName ?? "")|\(matchTitle)|\(piece.key)" }
        var needsReview: Bool { reviewReason != nil }
    }

    struct Result: Equatable {
        var matches: [ManualMatch]
        var addedCount: Int
        var updatedCount: Int
        /// Matches added or changed by the merge, in schedule order.
        var changedMatchIDs: [UUID]
        var notes: [Note]
    }

    static func merge(existing: [ManualMatch], incoming: [ManualMatch]) -> Result {
        var matches = existing
        var indexByKey: [ManualMatchKey: Int] = [:]
        for (index, match) in matches.enumerated() where indexByKey[match.sortKey] == nil {
            indexByKey[match.sortKey] = index
        }
        var usedIDs = Set(matches.map(\.id))
        var addedKeys = Set<ManualMatchKey>()
        var updatedKeys = Set<ManualMatchKey>()
        var notes: [Note] = []

        for match in incoming {
            let key = match.sortKey
            if let index = indexByKey[key] {
                let merged = mergeMatch(matches[index], with: match, notes: &notes)
                if merged != matches[index] {
                    matches[index] = merged
                    if !addedKeys.contains(key) { updatedKeys.insert(key) }
                }
            } else {
                var added = match
                if !usedIDs.insert(added.id).inserted {
                    added.id = UUID()
                    usedIDs.insert(added.id)
                }
                added.dropStaleEdits()
                indexByKey[key] = matches.count
                matches.append(added)
                addedKeys.insert(key)
            }
        }

        let changed = addedKeys.union(updatedKeys)
        return Result(
            matches: matches,
            addedCount: addedKeys.count,
            updatedCount: updatedKeys.count,
            changedMatchIDs: matches.filter { changed.contains($0.sortKey) }
                .sorted { $0.sortKey < $1.sortKey }
                .map(\.id),
            notes: notes.sorted { ($0.matchKey, $0.id) < ($1.matchKey, $1.id) }
        )
    }

    /// Merges several files one after another, in the order given. Counts and changed
    /// matches compare the final result with `existing`; notes name the file they came from.
    static func merge(existing: [ManualMatch], sources: [(name: String, matches: [ManualMatch])]) -> Result {
        var matches = existing
        var notes: [Note] = []
        for source in sources {
            let step = merge(existing: matches, incoming: source.matches)
            matches = step.matches
            notes += step.notes.map { note in
                var note = note
                note.sourceName = source.name
                return note
            }
        }

        let original = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var addedCount = 0
        var updatedCount = 0
        var changed: [ManualMatch] = []
        for match in matches {
            if let before = original[match.id] {
                guard before != match else { continue }
                updatedCount += 1
            } else {
                addedCount += 1
            }
            changed.append(match)
        }
        return Result(
            matches: matches,
            addedCount: addedCount,
            updatedCount: updatedCount,
            changedMatchIDs: changed.sorted { $0.sortKey < $1.sortKey }.map(\.id),
            notes: notes
        )
    }

    private enum Choice {
        case same
        case existing(contested: Bool)
        case incoming(contested: Bool)
    }

    private static func choose(_ piece: ManualMatchPiece, existing: ManualMatch, incoming: ManualMatch) -> Choice {
        guard existing.content(of: piece) != incoming.content(of: piece) else { return .same }
        if case .schedule = piece {
            // Typing an alliance's teams in the other order is not a disagreement.
            let mine = existing.schedule
            let theirs = incoming.schedule
            if mine.hasSameTeams(as: theirs), mine.entryStyle == theirs.entryStyle, mine.recording == theirs.recording {
                return .same
            }
        }
        let existingHas = existing.hasEntry(for: piece)
        let incomingHas = incoming.hasEntry(for: piece)
        if !incomingHas { return .existing(contested: false) }
        if !existingHas { return .incoming(contested: false) }
        let existingDate = existing.edits[piece.key]?.at ?? .distantPast
        let incomingDate = incoming.edits[piece.key]?.at ?? .distantPast
        return incomingDate > existingDate ? .incoming(contested: true) : .existing(contested: true)
    }

    private static func mergeMatch(
        _ existing: ManualMatch,
        with incoming: ManualMatch,
        notes: inout [Note]
    ) -> ManualMatch {
        var result = existing
        result.isScored = existing.isScored || incoming.isScored

        func note(_ piece: ManualMatchPiece, kept: Note.Source, reason: String? = nil) {
            let keptMatch = kept == .existing ? existing : incoming
            let replacedMatch = kept == .existing ? incoming : existing
            notes.append(Note(
                matchKey: existing.sortKey,
                matchTitle: existing.title,
                piece: piece,
                kept: kept,
                keptEdit: keptMatch.edits[piece.key],
                replacedEdit: replacedMatch.edits[piece.key],
                reviewReason: reason
            ))
        }

        func take(_ piece: ManualMatchPiece, from choice: Choice, apply: () -> Void) {
            switch choice {
            case .same:
                break
            case .existing(let contested):
                if contested { note(piece, kept: .existing) }
            case .incoming(let contested):
                apply()
                result.edits[piece.key] = incoming.edits[piece.key]
                if contested { note(piece, kept: .incoming) }
            }
        }

        // Teams first: they decide which team entries the merged match holds.
        let scheduleChoice = choose(.schedule, existing: existing, incoming: incoming)
        var losingSchedule: ManualMatch?
        switch scheduleChoice {
        case .same:
            break
        case .existing(let contested):
            if contested { losingSchedule = incoming }
        case .incoming(let contested):
            result.schedule = incoming.schedule
            result.edits[ManualMatchPiece.schedule.key] = incoming.edits[ManualMatchPiece.schedule.key]
            if contested { losingSchedule = existing }
        }
        if let losingSchedule {
            let kept: Note.Source = losingSchedule == incoming ? .existing : .incoming
            let differentTeams = !existing.schedule.hasSameTeams(as: incoming.schedule)
            let reason = differentTeams
                ? "The teams differ. The event has \(existing.schedule.teamsText); the file has \(incoming.schedule.teamsText)."
                : nil
            note(.schedule, kept: kept, reason: reason)
        }

        for alliance in [AllianceColor.red, .blue] {
            let piece = ManualMatchPiece.alliance(alliance)
            take(piece, from: choose(piece, existing: existing, incoming: incoming)) {
                result.setAllianceScoring(from: incoming.input(for: alliance), for: alliance)
            }
        }

        take(.flowers, from: choose(.flowers, existing: existing, incoming: incoming)) {
            result.flowers = incoming.flowers
        }

        // Team entries follow team numbers. When the schedule came from the file, the
        // slots now hold the file's teams, so every entry is written back explicitly.
        let resultTeams = Set(result.redTeams + result.blueTeams)
        for team in result.pieces.compactMap({ piece -> Int? in
            if case .team(let number) = piece { number } else { nil }
        }) {
            let piece = ManualMatchPiece.team(team)
            let existingEntry = existing.teamEntry(for: team)
            let incomingEntry = incoming.teamEntry(for: team)
            let choice: Choice = switch (existingEntry, incomingEntry) {
            case (nil, _): .incoming(contested: false)
            case (_, nil): .existing(contested: false)
            default: choose(piece, existing: existing, incoming: incoming)
            }
            switch choice {
            case .same, .existing:
                result.setTeamEntry(existingEntry ?? ManualTeamEntry(), for: team)
                result.edits[piece.key] = existing.edits[piece.key]
                if case .existing(contested: true) = choice { note(piece, kept: .existing) }
            case .incoming(let contested):
                result.setTeamEntry(incomingEntry ?? ManualTeamEntry(), for: team)
                result.edits[piece.key] = incoming.edits[piece.key]
                if contested { note(piece, kept: .incoming) }
            }
        }

        // Entries for teams the merged schedule dropped cannot be kept.
        for source in [existing, incoming] {
            for team in Set(source.redTeams + source.blueTeams).subtracting(resultTeams).sorted() {
                let piece = ManualMatchPiece.team(team)
                guard source.hasEntry(for: piece) else { continue }
                notes.append(Note(
                    matchKey: existing.sortKey,
                    matchTitle: existing.title,
                    piece: piece,
                    kept: source == existing ? .incoming : .existing,
                    keptEdit: nil,
                    replacedEdit: source.edits[piece.key],
                    reviewReason: "Team \(team.teamNumberText) is not in the merged match, so its entries from \(source == existing ? "the event" : "the file") were not kept."
                ))
            }
        }

        result.dropStaleEdits()
        return result
    }
}

/// What importing a CSV or merging a scout file did to a manual event.
struct ManualImportOutcome: Equatable {
    /// CSV rows that could not be read; empty for scout files.
    var issues: [ManualEventCSV.ImportIssue]
    var usedMatchDetailsFormat: Bool
    var merge: ManualEventMerge.Result
    /// Scout files that could not be merged, each with the reason.
    var failures: [String] = []
}

enum ManualScoutFileError: LocalizedError {
    case unreadable
    case seasonMismatch(file: String, event: String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "It is not a scout file exported from FTC Event Scout."
        case .seasonMismatch(let file, let event):
            "It is from the \(file) season, but this event is \(event)."
        }
    }
}
