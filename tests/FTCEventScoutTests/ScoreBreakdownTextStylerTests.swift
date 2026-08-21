import XCTest
@testable import FTCEventScout

final class ScoreBreakdownTextStylerTests: XCTestCase {
    func testScoreNumbersReceiveAllianceRole() {
        XCTAssertEqual(
            ScoreBreakdownTextStyler.segments(
                in: "12 / 3.5 · -4",
                usesDecodePatternColors: false
            ),
            [
                ScoreBreakdownTextSegment(text: "12", role: .alliance),
                ScoreBreakdownTextSegment(text: " / ", role: .standard),
                ScoreBreakdownTextSegment(text: "3.5", role: .alliance),
                ScoreBreakdownTextSegment(text: " · ", role: .standard),
                ScoreBreakdownTextSegment(text: "-4", role: .alliance),
            ]
        )
    }

    func testDecodePatternLettersReceiveIndividualRoles() {
        XCTAssertEqual(
            ScoreBreakdownTextStyler.segments(
                in: "G / P / N",
                usesDecodePatternColors: true
            ),
            [
                ScoreBreakdownTextSegment(text: "G", role: .decodeGreen),
                ScoreBreakdownTextSegment(text: " / ", role: .standard),
                ScoreBreakdownTextSegment(text: "P", role: .decodePurple),
                ScoreBreakdownTextSegment(text: " / ", role: .standard),
                ScoreBreakdownTextSegment(text: "N", role: .decodeNone),
            ]
        )
    }

    func testNonScoreStatusesRemainNeutral() {
        XCTAssertEqual(
            ScoreBreakdownTextStyler.segments(
                in: "Full · Partial",
                usesDecodePatternColors: false
            ),
            [ScoreBreakdownTextSegment(text: "Full · Partial", role: .standard)]
        )
    }
}
