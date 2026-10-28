import XCTest
@testable import SpaceLogic

final class SpaceDiffTests: XCTestCase {
    func testNoChange() {
        let s: CurrentSpaces = ["A": 1, "B": 10]
        XCTAssertEqual(SpaceDiff.changedDisplays(old: s, new: s), [])
    }

    func testSingleDisplayChange() {
        let r = SpaceDiff.changedDisplays(old: ["A": 1, "B": 10], new: ["A": 3, "B": 10])
        XCTAssertEqual(r, [.init(displayUUID: "A", from: 1, to: 3)])
    }

    func testBothDisplaysChangeSortedByUUID() {
        let r = SpaceDiff.changedDisplays(old: ["B": 10, "A": 1], new: ["B": 11, "A": 2])
        XCTAssertEqual(r.map(\.displayUUID), ["A", "B"])
    }

    func testDisplayOnlyInNewIsIgnored() {
        XCTAssertEqual(SpaceDiff.changedDisplays(old: ["A": 1], new: ["A": 1, "B": 10]), [])
    }

    func testDisplayOnlyInOldIsIgnored() {
        XCTAssertEqual(SpaceDiff.changedDisplays(old: ["A": 1, "B": 10], new: ["A": 1]), [])
    }

    func testEmptySnapshots() {
        XCTAssertEqual(SpaceDiff.changedDisplays(old: [:], new: [:]), [])
    }
}
