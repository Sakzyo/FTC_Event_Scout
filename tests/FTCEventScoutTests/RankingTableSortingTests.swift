import XCTest
@testable import FTCEventScout

final class RankingTableSortingTests: XCTestCase {
    func testMetricColumnsSortStrongestFirstAndIdentifiersAscend() {
        let forward: [RankingSortField] = [.storedRank, .teamNumber, .teamName, .rookieYear]
        let reverse: [RankingSortField] = [
            .totalOPR, .oprc, .nonPenaltyOPR, .autoOPR, .teleopOPR, .endgameOPR,
            .highestOPR, .bestSeason,
        ]

        XCTAssertEqual(Set(forward + reverse), Set(RankingSortField.allCases))
        for field in forward {
            XCTAssertEqual(field.defaultTableSortOrder, .forward, "\(field)")
        }
        for field in reverse {
            XCTAssertEqual(field.defaultTableSortOrder, .reverse, "\(field)")
        }
    }

    func testComparatorDefaultsToTheFieldsNaturalDirection() {
        XCTAssertEqual(RankingColumnComparator(.oprc).order, .reverse)
        XCTAssertEqual(RankingColumnComparator(.teamNumber).order, .forward)
        XCTAssertEqual(
            RankingColumnComparator(.oprc, order: .forward).order,
            .forward
        )
    }

    func testSortedColumnScaleSizesBarsRelativeToTheLargestValue() {
        let scale = SortedColumnScale(field: .totalOPR, values: [80, 40, nil, -5, .nan])

        XCTAssertTrue(scale.isSorted(.totalOPR))
        XCTAssertFalse(scale.isSorted(.autoOPR))
        XCTAssertEqual(scale.fraction(for: 80, in: .totalOPR), 1)
        XCTAssertEqual(scale.fraction(for: 40, in: .totalOPR), 0.5)
        XCTAssertEqual(scale.fraction(for: -5, in: .totalOPR), 0)
        XCTAssertEqual(scale.fraction(for: nil, in: .totalOPR), 0)
        XCTAssertEqual(scale.fraction(for: 40, in: .autoOPR), 0)
    }

    func testSortedColumnScaleWithoutPositiveValuesDrawsNoBars() {
        let scale = SortedColumnScale(field: .endgameOPR, values: [-3, nil])

        XCTAssertEqual(scale.fraction(for: 2, in: .endgameOPR), 0)
    }
}
