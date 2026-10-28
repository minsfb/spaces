import XCTest
@testable import SpaceLogic

final class GestureFollowerTests: XCTestCase {
    // Two displays: L (laptop) and X (external). Groups: A = (L:1, X:10), B = (L:2, X:11).
    let gA = FollowGroup(id: UUID(), targets: ["L": 1, "X": 10])
    let gB = FollowGroup(id: UUID(), targets: ["L": 2, "X": 11])
    var groups: [FollowGroup] { [gA, gB] }

    func testSwipeOnLaptopMakesExternalFollow() {
        var f = GestureFollower()
        let r = f.handle(old: ["L": 1, "X": 10], new: ["L": 2, "X": 10], groups: groups, now: 0)
        XCTAssertEqual(r, [SwitchRequest(displayUUID: "X", spaceID: 11)])
    }

    func testSwipeOnExternalMakesLaptopFollow() {
        var f = GestureFollower()
        let r = f.handle(old: ["L": 1, "X": 10], new: ["L": 1, "X": 11], groups: groups, now: 0)
        XCTAssertEqual(r, [SwitchRequest(displayUUID: "L", spaceID: 2)])
    }

    func testOurOwnSwitchDoesNotTriggerFeedback() {
        var f = GestureFollower()
        _ = f.handle(old: ["L": 1, "X": 10], new: ["L": 2, "X": 10], groups: groups, now: 0)
        // external lands on 11 as requested -> nothing more to do
        let r = f.handle(old: ["L": 2, "X": 10], new: ["L": 2, "X": 11], groups: groups, now: 0.3)
        XCTAssertEqual(r, [])
    }

    func testUngroupedSpaceIsIgnored() {
        var f = GestureFollower()
        let r = f.handle(old: ["L": 1, "X": 10], new: ["L": 5, "X": 10], groups: groups, now: 0)
        XCTAssertEqual(r, [])
    }

    func testAlreadyAlignedNeedsNoSwitch() {
        var f = GestureFollower()
        let r = f.handle(old: ["L": 1, "X": 11], new: ["L": 2, "X": 11], groups: groups, now: 0)
        XCTAssertEqual(r, [])
    }

    func testNoChangeNoRequests() {
        var f = GestureFollower()
        XCTAssertEqual(f.handle(old: ["L": 1, "X": 10], new: ["L": 1, "X": 10], groups: groups, now: 0), [])
    }

    func testUserOverridesPendingRequest() {
        var f = GestureFollower()
        _ = f.handle(old: ["L": 1, "X": 10], new: ["L": 2, "X": 10], groups: groups, now: 0)   // wants X -> 11
        // before X moved, user swipes laptop back to 1 -> X should follow group A (already on 10 => no switch)
        let r = f.handle(old: ["L": 2, "X": 10], new: ["L": 1, "X": 10], groups: groups, now: 0.1)
        XCTAssertEqual(r, [])
    }

    func testRapidSwipesEachProduceTheirOwnRequest() {
        var f = GestureFollower()
        let r1 = f.handle(old: ["L": 1, "X": 10], new: ["L": 2, "X": 10], groups: groups, now: 0)
        XCTAssertEqual(r1, [SwitchRequest(displayUUID: "X", spaceID: 11)])
        // user swipes back before external switched
        let r2 = f.handle(old: ["L": 2, "X": 10], new: ["L": 1, "X": 10], groups: groups, now: 0.05)
        XCTAssertEqual(r2, [])
        // stale pending for X must be gone: a later external change to 11 is user input
        let r3 = f.handle(old: ["L": 1, "X": 10], new: ["L": 1, "X": 11], groups: groups, now: 0.2)
        XCTAssertEqual(r3, [SwitchRequest(displayUUID: "L", spaceID: 2)])
    }

    func testExpiredPendingChangeIsTreatedAsUserInput() {
        var f = GestureFollower(pendingTTL: 1.0)
        // we asked X -> 11 (after laptop went to 2)
        _ = f.handle(old: ["L": 1, "X": 10], new: ["L": 2, "X": 10], groups: groups, now: 0)
        // 5 s later, laptop is back on 1 (e.g. changed without us noticing) and X lands on 11 by user: laptop must follow
        let r = f.handle(old: ["L": 1, "X": 10], new: ["L": 1, "X": 11], groups: groups, now: 5)
        XCTAssertEqual(r, [SwitchRequest(displayUUID: "L", spaceID: 2)])
    }

    func testDisconnectedDisplayIsSkipped() {
        var f = GestureFollower()
        let r = f.handle(old: ["L": 1], new: ["L": 2], groups: groups, now: 0)
        XCTAssertEqual(r, [])
    }

    func testThreeDisplaysAllFollow() {
        let g = FollowGroup(id: UUID(), targets: ["A": 1, "B": 20, "C": 30])
        let h = FollowGroup(id: UUID(), targets: ["A": 2, "B": 21, "C": 31])
        var f = GestureFollower()
        let r = f.handle(old: ["A": 1, "B": 20, "C": 30], new: ["A": 1, "B": 21, "C": 30], groups: [g, h], now: 0)
        XCTAssertEqual(r, [SwitchRequest(displayUUID: "A", spaceID: 2), SwitchRequest(displayUUID: "C", spaceID: 31)])
    }

    func testFirstMatchingGroupWinsWhenAmbiguous() {
        let g1 = FollowGroup(id: UUID(), targets: ["L": 1, "X": 10])
        let g2 = FollowGroup(id: UUID(), targets: ["L": 1, "X": 12])   // also uses L:1
        var f = GestureFollower()
        // user moves L to 3 first (so X stays), then to 1: g1 comes first in order
        let r = f.handle(old: ["L": 3, "X": 11], new: ["L": 1, "X": 11], groups: [g1, g2], now: 0)
        XCTAssertEqual(r, [SwitchRequest(displayUUID: "X", spaceID: 10)])
    }

    func testGroupThatOnlyCoversOneDisplayDoesNothingElse() {
        let solo = FollowGroup(id: UUID(), targets: ["L": 4])
        var f = GestureFollower()
        XCTAssertEqual(f.handle(old: ["L": 1, "X": 10], new: ["L": 4, "X": 10], groups: [solo], now: 0), [])
    }
}
