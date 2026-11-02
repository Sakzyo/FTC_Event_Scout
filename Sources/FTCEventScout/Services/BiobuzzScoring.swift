import Foundation

/// BIOBUZZ (2026–2027) point values from Competition Manual V1, Tables 10-2 to 10-4.
/// The official FIRST Events fixtures in `tests/fixtures/biobuzz_*.json` reproduce exactly.
enum BiobuzzScoring {
    static let season = 2026

    static let leavePoints = 3
    static let autoParkPoints = 5
    static let teleopParkPoints = 5
    static let hiveTipPoints = 20
    static let hivePollenNectarPoints = 2
    static let gardenPollenNectarPoints = 1
    static let ownedFlowerElementPoints = 2
    static let bottomNectarBonusPoints = 5
    static let minorFoulPoints = 5
    static let majorFoulPoints = 20

    static let swarmThreshold = 16
    static let pollinator1TipThreshold = 4
    static let pollinator2TipThreshold = 7

    struct AllianceResult: Equatable {
        let autoLeavePoints: Int
        let autoParkPoints: Int
        let autoHivePoints: Int
        let teleopHivePoints: Int
        let teleopFlowerPoints: Int
        let teleopGardenPoints: Int
        let teleopParkPoints: Int
        let foulPointsCommitted: Int
        let swarmRP: Bool
        let pollinator1RP: Bool
        let pollinator2RP: Bool

        var autoPoints: Int { autoLeavePoints + autoParkPoints + autoHivePoints }
        var teleopPoints: Int {
            teleopHivePoints + teleopFlowerPoints + teleopGardenPoints + teleopParkPoints
        }
        var preFoulTotal: Int { autoPoints + teleopPoints }

        func value(for field: BiobuzzPointField) -> Int {
            switch field {
            case .autoLeave: autoLeavePoints
            case .autoPark: autoParkPoints
            case .autoHive: autoHivePoints
            case .teleopHive: teleopHivePoints
            case .teleopFlower: teleopFlowerPoints
            case .teleopGarden: teleopGardenPoints
            case .teleopPark: teleopParkPoints
            case .foulsCommitted: foulPointsCommitted
            }
        }
    }

    /// Points for one alliance with the scout's overrides applied.
    static func score(
        _ input: BiobuzzAllianceInput,
        alliance: AllianceColor,
        flowers: BiobuzzFlowers
    ) -> AllianceResult {
        let calculated = calculatedScore(input, alliance: alliance, flowers: flowers)
        func resolved(_ field: BiobuzzPointField) -> Int {
            input.override(for: field) ?? calculated.value(for: field)
        }
        let leave = resolved(.autoLeave)
        let autoPark = resolved(.autoPark)
        let teleopPark = resolved(.teleopPark)
        let tips = input.autoHiveTips + input.teleopHiveTips
        return AllianceResult(
            autoLeavePoints: leave,
            autoParkPoints: autoPark,
            autoHivePoints: resolved(.autoHive),
            teleopHivePoints: resolved(.teleopHive),
            teleopFlowerPoints: resolved(.teleopFlower),
            teleopGardenPoints: resolved(.teleopGarden),
            teleopParkPoints: teleopPark,
            foulPointsCommitted: resolved(.foulsCommitted),
            swarmRP: leave + autoPark + teleopPark >= swarmThreshold,
            pollinator1RP: tips >= pollinator1TipThreshold,
            pollinator2RP: tips >= pollinator2TipThreshold
        )
    }

    /// Points for one alliance straight from the rules, ignoring overrides.
    static func calculatedScore(
        _ input: BiobuzzAllianceInput,
        alliance: AllianceColor,
        flowers: BiobuzzFlowers
    ) -> AllianceResult {
        let leaving = [input.autoRobot1Leave, input.autoRobot2Leave].filter { $0 }.count
        let autoParked = [input.autoRobot1Park, input.autoRobot2Park].filter { $0 }.count
        let teleopParked = [input.teleopRobot1Park, input.teleopRobot2Park].filter { $0 }.count
        let tips = input.autoHiveTips + input.teleopHiveTips
        let leavePoints = leaving * leavePoints
        let autoPark = autoParked * autoParkPoints
        let teleopPark = teleopParked * teleopParkPoints
        return AllianceResult(
            autoLeavePoints: leavePoints,
            autoParkPoints: autoPark,
            autoHivePoints: input.autoHiveTips * hiveTipPoints,
            teleopHivePoints: input.teleopHiveTips * hiveTipPoints
                + input.teleopHivePollenNectar * hivePollenNectarPoints,
            teleopFlowerPoints: flowerPoints(for: alliance, flowers: flowers),
            teleopGardenPoints: input.teleopGardenPollenNectar * gardenPollenNectarPoints,
            teleopParkPoints: teleopPark,
            foulPointsCommitted: input.minorFouls * minorFoulPoints
                + input.majorFouls * majorFoulPoints,
            swarmRP: leavePoints + autoPark + teleopPark >= swarmThreshold,
            pollinator1RP: tips >= pollinator1TipThreshold,
            pollinator2RP: tips >= pollinator2TipThreshold
        )
    }

    /// The alliance whose nectar is top-most owns a flower and scores every element in it.
    /// Each alliance with a nectar in a flower also earns the bottom-nectar bonus.
    static func flowerPoints(for alliance: AllianceColor, flowers: BiobuzzFlowers) -> Int {
        BiobuzzFlower.allCases.reduce(0) { total, flower in
            let elements = flowers[flower]
            let nectars = elements.compactMap(\.nectarAlliance)
            var points = 0
            if nectars.last == alliance {
                points += elements.count * ownedFlowerElementPoints
            }
            if nectars.contains(alliance) {
                points += bottomNectarBonusPoints
            }
            return total + points
        }
    }

    /// Display rows in the same order, ids, and labels as `score_breakdown.py`,
    /// so manual matches render exactly like FIRST Events matches.
    static func breakdownDetails(
        input: BiobuzzAllianceInput,
        result: AllianceResult,
        opponentInput: BiobuzzAllianceInput,
        flowers: BiobuzzFlowers,
        penaltyAwarded: Int,
        final: Int
    ) -> [ScoreBreakdownDetail] {
        func row(_ id: String, _ label: String, _ value: String, indent: Int = 1, emphasized: Bool = false) -> ScoreBreakdownDetail {
            ScoreBreakdownDetail(id: id, label: label, value: value, indent: indent, emphasized: emphasized)
        }
        func pair(_ first: Bool, _ second: Bool) -> String {
            "\(yesNo(first)) · \(yesNo(second))"
        }
        func flower(_ elements: [BiobuzzFlowerElement]) -> String {
            elements.isEmpty ? "Empty" : elements.map(\.title).joined(separator: " / ")
        }

        return [
            row("auto", "Auto", String(result.autoPoints), indent: 0, emphasized: true),
            row("auto-hive-tips", "Hive Tips", String(input.autoHiveTips)),
            row("auto-leave", "Leave (Robot 1 / 2)", pair(input.autoRobot1Leave, input.autoRobot2Leave)),
            row("auto-park", "Park (Robot 1 / 2)", pair(input.autoRobot1Park, input.autoRobot2Park)),
            row("auto-leave-points", "Leave Points", String(result.autoLeavePoints)),
            row("auto-park-points", "Park Points", String(result.autoParkPoints)),
            row("auto-hive-points", "Hive Points", String(result.autoHivePoints)),
            row("teleop", "Teleop", String(result.teleopPoints), indent: 0, emphasized: true),
            row("teleop-hive-tips", "Hive Tips", String(input.teleopHiveTips)),
            row("teleop-hive-pollen-nectar", "Hive Pollen / Nectar Remaining", String(input.teleopHivePollenNectar)),
            row("teleop-flower-red", "Red Alliance Flower", flower(flowers.redAlliance)),
            row("teleop-flower-scoring", "Scoring Flower", flower(flowers.scoring)),
            row("teleop-flower-blue", "Blue Alliance Flower", flower(flowers.blueAlliance)),
            row("teleop-flower-audience", "Audience Flower", flower(flowers.audience)),
            row("teleop-garden-pollen-nectar", "Garden Pollen / Nectar", String(input.teleopGardenPollenNectar)),
            row("teleop-park", "Park (Robot 1 / 2)", pair(input.teleopRobot1Park, input.teleopRobot2Park)),
            row("teleop-hive-points", "Hive Points", String(result.teleopHivePoints)),
            row("teleop-flower-points", "Flower Points", String(result.teleopFlowerPoints)),
            row("teleop-garden-points", "Garden Points", String(result.teleopGardenPoints)),
            row("teleop-park-points", "Park Points", String(result.teleopParkPoints)),
            row("penalty", "Penalty Points Awarded", String(penaltyAwarded), indent: 0, emphasized: true),
            row("penalty-minor", "Opponent Minor Fouls", String(opponentInput.minorFouls)),
            row("penalty-major", "Opponent Major Fouls", String(opponentInput.majorFouls)),
            row("final", "Final Score", String(final), indent: 0, emphasized: true),
            row("rp-swarm", "Swarm RP", yesNo(result.swarmRP), indent: 0),
            row("rp-pollinator-1", "Pollinator 1 RP", yesNo(result.pollinator1RP), indent: 0),
            row("rp-pollinator-2", "Pollinator 2 RP", yesNo(result.pollinator2RP), indent: 0),
        ]
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}
