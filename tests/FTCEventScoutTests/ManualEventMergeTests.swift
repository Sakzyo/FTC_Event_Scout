import XCTest
@testable import FTCEventScout

final class ManualEventMergeTests: XCTestCase {
    private let early = Date(timeIntervalSince1970: 1_800_000_000)
    private var late: Date { early.addingTimeInterval(60) }

    /// Q1: red 101 & 102, blue 201 & 202, per-team BIOBUZZ entry.
    private func scheduled(_ number: Int = 1) -> ManualMatch {
        ManualMatch(
            number: number,
            red1: 101, red2: 102, blue1: 201, blue2: 202,
            entryStyle: .detailed, recording: .perTeam
        )
    }

    private func edited(_ match: ManualMatch, by scout: String, at date: Date, _ change: (inout ManualMatch) -> Void) -> ManualMatch {
        var updated = match
        change(&updated)
        return updated.recordingEdits(since: match, by: scout, at: date)
    }

    // MARK: Stamping

    func testEditsStampOnlyThePartsThatChanged() {
        let base = scheduled()
        let match = edited(base, by: "Ava", at: early) {
            $0.red.biobuzz.robot1.autoHiveCycles = 2
            $0.blue.biobuzz.teleopHivePollenNectar = 4
        }

        XCTAssertEqual(Set(match.edits.keys), ["team-101", "blue"])
        XCTAssertEqual(match.edits["team-101"], ManualEdit(at: early, by: "Ava"))
    }

    func testNewMatchStampsOnlyPartsWithEntries() {
        let match = scheduled().recordingEdits(since: nil, by: "Ava", at: early)
        XCTAssertEqual(Set(match.edits.keys), ["schedule"])
    }

    func testTeamStampFollowsCorrectedTeamNumber() {
        var base = scheduled()
        base.red.biobuzz.robot1.autoHiveCycles = 3
        base.edits["team-101"] = ManualEdit(at: early, by: "Ava")
        let match = edited(base, by: "Ava", at: late) { $0.red1 = 110 }

        XCTAssertNil(match.edits["team-101"])
        XCTAssertEqual(match.edits["team-110"]?.at, late)
        XCTAssertEqual(match.teamEntry(for: 110)?.autoHiveCycles, 3)
    }

    // MARK: Merging

    func testScoutsWatchingDifferentRobotsCombine() {
        let base = scheduled()
        let ava = edited(base, by: "Ava", at: early) {
            $0.red.biobuzz.robot1.autoHiveCycles = 2
            $0.red.biobuzz.robot1.teleopHiveCycles = 5
            $0.red.biobuzz.autoRobot1Leave = true
            $0.isScored = true
        }
        let ben = edited(base, by: "Ben", at: late) {
            $0.blue.biobuzz.robot2.teleopHiveCycles = 7
            $0.blue.biobuzz.teleopRobot2Park = true
        }

        let result = ManualEventMerge.merge(existing: [ava], incoming: [ben])
        let merged = result.matches[0]

        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertEqual(result.notes, [])
        XCTAssertEqual(merged.teamEntry(for: 101), ManualTeamEntry(autoHiveCycles: 2, teleopHiveCycles: 5, autoLeave: true))
        XCTAssertEqual(merged.teamEntry(for: 202), ManualTeamEntry(teleopHiveCycles: 7, teleopPark: true))
        XCTAssertEqual(merged.edits["team-101"]?.by, "Ava")
        XCTAssertEqual(merged.edits["team-202"]?.by, "Ben")
        XCTAssertTrue(merged.isScored)
    }

    func testBlankTeamEntryNeverReplacesRecordedCycles() {
        let base = scheduled()
        let recorded = edited(base, by: "Ava", at: early) { $0.red.biobuzz.robot1.teleopHiveCycles = 6 }
        // A newer file that never touched team 101: its zeros are not an entry.
        let blank = edited(base, by: "Ben", at: late) { $0.blue.biobuzz.minorFouls = 1 }

        let merged = ManualEventMerge.merge(existing: [recorded], incoming: [blank]).matches[0]
        XCTAssertEqual(merged.teamEntry(for: 101)?.teleopHiveCycles, 6)

        // And the other way round.
        let reversed = ManualEventMerge.merge(existing: [blank], incoming: [recorded]).matches[0]
        XCTAssertEqual(reversed.teamEntry(for: 101)?.teleopHiveCycles, 6)
    }

    func testRecordedZeroReplacesOlderEntry() {
        let base = scheduled()
        let wrong = edited(base, by: "Ava", at: early) { $0.red.biobuzz.robot1.teleopHiveCycles = 4 }
        let corrected = edited(wrong, by: "Ben", at: late) { $0.red.biobuzz.robot1.teleopHiveCycles = 0 }

        let result = ManualEventMerge.merge(existing: [wrong], incoming: [corrected])
        XCTAssertEqual(result.matches[0].teamEntry(for: 101)?.teleopHiveCycles, 0)
        XCTAssertEqual(result.notes.map(\.piece), [.team(101)])
        XCTAssertEqual(result.notes.first?.kept, .incoming)
    }

    func testCyclesFollowTeamNumberWhenSlotsAreSwapped() {
        let base = scheduled()
        let ava = edited(base, by: "Ava", at: early) { $0.red.biobuzz.robot1.teleopHiveCycles = 3 }
        var swappedBase = base
        swap(&swappedBase.red1, &swappedBase.red2)
        // Ben typed 102 first, so his robot 1 is team 102.
        let ben = edited(swappedBase, by: "Ben", at: late) { $0.red.biobuzz.robot1.teleopHiveCycles = 8 }

        let result = ManualEventMerge.merge(existing: [ava], incoming: [ben])
        let merged = result.matches[0]

        XCTAssertEqual(merged.teamEntry(for: 101)?.teleopHiveCycles, 3)
        XCTAssertEqual(merged.teamEntry(for: 102)?.teleopHiveCycles, 8)
        XCTAssertFalse(result.notes.contains(where: \.needsReview))
    }

    func testNewerEntryWinsAndIsListed() {
        let base = scheduled()
        let ava = edited(base, by: "Ava", at: early) { $0.red.biobuzz.teleopHivePollenNectar = 3 }
        let ben = edited(base, by: "Ben", at: late) { $0.red.biobuzz.teleopHivePollenNectar = 5 }

        for (existing, incoming) in [(ava, ben), (ben, ava)] {
            let result = ManualEventMerge.merge(existing: [existing], incoming: [incoming])
            XCTAssertEqual(result.matches[0].red.biobuzz.teleopHivePollenNectar, 5)
            XCTAssertEqual(result.notes.count, 1)
            XCTAssertEqual(result.notes[0].piece, .alliance(.red))
            XCTAssertEqual(result.notes[0].keptEdit?.by, "Ben")
            XCTAssertEqual(result.notes[0].replacedEdit?.by, "Ava")
            XCTAssertFalse(result.notes[0].needsReview)
        }
    }

    func testAllianceScoringMergeKeepsRobotEntries() {
        let base = scheduled()
        let ava = edited(base, by: "Ava", at: early) { $0.red.biobuzz.robot2.autoHiveCycles = 2 }
        let ben = edited(base, by: "Ben", at: late) { $0.red.biobuzz.majorFouls = 1 }

        let merged = ManualEventMerge.merge(existing: [ava], incoming: [ben]).matches[0]
        XCTAssertEqual(merged.red.biobuzz.majorFouls, 1)
        XCTAssertEqual(merged.red.biobuzz.robot2.autoHiveCycles, 2)
    }

    func testDifferentTeamsAreFlaggedForReview() {
        let ava = edited(scheduled(), by: "Ava", at: early) { $0.red.biobuzz.robot2.autoHiveCycles = 1 }
        var benBase = scheduled()
        benBase.red2 = 103
        benBase.edits["schedule"] = ManualEdit(at: late, by: "Ben")

        let result = ManualEventMerge.merge(existing: [ava], incoming: [benBase])
        let merged = result.matches[0]

        XCTAssertEqual(merged.red2, 103)
        let review = result.notes.filter(\.needsReview)
        XCTAssertEqual(review.map(\.piece), [.schedule, .team(102)])
        XCTAssertNil(merged.edits["team-102"])
    }

    func testUnstampedCSVRowsFillGapsButKeepStampedEntries() {
        let base = scheduled()
        let ava = edited(base, by: "Ava", at: early) { $0.red.totals.auto = 20 }
        var row = base
        row.red.totals.auto = 25
        row.blue.totals.auto = 30

        let result = ManualEventMerge.merge(existing: [ava], incoming: [row])
        XCTAssertEqual(result.matches[0].red.totals.auto, 20)
        XCTAssertEqual(result.matches[0].blue.totals.auto, 30)
        XCTAssertEqual(result.notes.map(\.kept), [.existing])
    }

    func testNewMatchesAreAddedAndKeptMatchesStay() {
        let existing = [scheduled(1), scheduled(2)]
        var incoming = scheduled(3)
        incoming.id = existing[0].id

        let result = ManualEventMerge.merge(existing: existing, incoming: [incoming])

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.updatedCount, 0)
        XCTAssertEqual(result.matches.map(\.number), [1, 2, 3])
        XCTAssertEqual(Set(result.matches.map(\.id)).count, 3)
        XCTAssertEqual(result.changedMatchIDs, [result.matches[2].id])
    }

    func testMergingTheSameFileTwiceChangesNothing() {
        let base = scheduled()
        let ben = edited(base, by: "Ben", at: late) { $0.blue.biobuzz.robot1.autoHiveCycles = 2 }
        let once = ManualEventMerge.merge(existing: [base], incoming: [ben])
        let twice = ManualEventMerge.merge(existing: once.matches, incoming: [ben])

        XCTAssertEqual(twice.matches, once.matches)
        XCTAssertEqual(twice.updatedCount, 0)
        XCTAssertEqual(twice.notes, [])
    }

    func testSeveralFilesMergeInOrderAndNameTheirNotes() {
        let base = scheduled()
        let ava = edited(base, by: "Ava", at: early) {
            $0.red.biobuzz.robot1.teleopHiveCycles = 4
            $0.blue.biobuzz.teleopHivePollenNectar = 2
        }
        let ben = edited(base, by: "Ben", at: late) {
            $0.blue.biobuzz.robot2.teleopHiveCycles = 6
            $0.blue.biobuzz.teleopHivePollenNectar = 3
        }
        let cara = scheduled(2)

        let result = ManualEventMerge.merge(
            existing: [base],
            sources: [("Ava.json", [ava]), ("Ben.json", [ben, cara])]
        )
        let merged = result.matches[0]

        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.changedMatchIDs, result.matches.map(\.id))
        XCTAssertEqual(merged.teamEntry(for: 101)?.teleopHiveCycles, 4)
        XCTAssertEqual(merged.teamEntry(for: 202)?.teleopHiveCycles, 6)
        XCTAssertEqual(merged.blue.biobuzz.teleopHivePollenNectar, 3)
        XCTAssertEqual(result.notes.map(\.sourceName), ["Ben.json"])
        XCTAssertEqual(result.notes.first?.kept, .incoming)
    }

    func testNoFilesChangesNothing() {
        let result = ManualEventMerge.merge(existing: [scheduled()], sources: [])
        XCTAssertEqual(result.addedCount + result.updatedCount, 0)
        XCTAssertEqual(result.notes, [])
    }

    // MARK: Files

    func testScoutFileRoundTripKeepsEdits() throws {
        let match = edited(scheduled(), by: "Ava", at: early) { $0.red.biobuzz.robot1.autoHiveCycles = 2 }
        let event = ManualEvent(name: "Scrimmage", season: 2026, matches: [match])

        let decoded = try ManualEventStore.decoded(ManualEventStore.encoded(event))
        XCTAssertEqual(decoded.matches, event.matches)
    }

    func testMatchesSavedBeforeMergingDecodeWithoutEdits() throws {
        let event = ManualEvent(name: "Old", season: 2026, matches: [scheduled()])
        var json = try JSONSerialization.jsonObject(with: ManualEventStore.encoded(event)) as! [String: Any]
        var matches = json["matches"] as! [[String: Any]]
        matches[0].removeValue(forKey: "edits")
        json["matches"] = matches

        let decoded = try ManualEventStore.decoded(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.matches[0].edits, [:])
        XCTAssertEqual(decoded.matches[0].red1, 101)
    }
}
