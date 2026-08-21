import Foundation

enum ScoreBreakdownTextRole: Equatable {
    case standard
    case alliance
    case decodeGreen
    case decodePurple
    case decodeNone
}

struct ScoreBreakdownTextSegment: Equatable {
    var text: String
    let role: ScoreBreakdownTextRole
}

enum ScoreBreakdownTextStyler {
    private static let numericPunctuation: Set<Character> = [".", ",", "+", "-"]

    static func segments(
        in value: String,
        usesDecodePatternColors: Bool
    ) -> [ScoreBreakdownTextSegment] {
        var segments: [ScoreBreakdownTextSegment] = []

        for character in value {
            let role = role(
                for: character,
                usesDecodePatternColors: usesDecodePatternColors
            )
            if let lastIndex = segments.indices.last, segments[lastIndex].role == role {
                segments[lastIndex].text.append(character)
            } else {
                segments.append(ScoreBreakdownTextSegment(
                    text: String(character),
                    role: role
                ))
            }
        }

        return segments
    }

    private static func role(
        for character: Character,
        usesDecodePatternColors: Bool
    ) -> ScoreBreakdownTextRole {
        if usesDecodePatternColors {
            switch character {
            case "G": return .decodeGreen
            case "P": return .decodePurple
            case "N": return .decodeNone
            default: break
            }
        }

        if character.wholeNumberValue != nil || numericPunctuation.contains(character) {
            return .alliance
        }
        return .standard
    }
}
