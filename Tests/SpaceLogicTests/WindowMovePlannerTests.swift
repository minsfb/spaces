import XCTest
@testable import SpaceLogic

final class WindowMovePlannerTests: XCTestCase {
    func loc(_ d: String, _ k: String) -> WindowLocation { WindowLocation(displayUUID: d, spaceKey: k) }
    func win(_ id: Int, _ d: String, _ k: String, pid: Int = 100) -> TrackedWindow { TrackedWindow(id: id, pid: pid, location: loc(d, k)) }

    // Groups: A = (L:L-3, X:X-A), B = (L:L-4, X:X-B). X-C is ungrouped.
    let groups = [
        GroupSpec(id: UUID(), spaces: ["L": "L-3", "X": "X-A"]),
        GroupSpec(id: UUID(), spaces: ["L": "L-4", "X": "X-B"]),
    ]

    var before: WindowSnapshot {
        WindowSnapshot(time: 1, displays: ["L", "X"], windows: [
            win(1, "X", "X-A"), win(2, "X", "X-B"), win(3, "L", "L-3"), win(4, "X", "X-C"),
        ], bootSession: 1)
    }

    // Observed on macOS 26: the removed display's first Space folds into the laptop's primary Space; its other
    // Spaces are appended to the laptop's Space list with their windows still in them.
    var afterDisconnectCurrent: [Int: TrackedWindow] {
        [1: win(1, "L", "primary"), 2: win(2, "L", "X-B"), 3: win(3, "L", "L-3"), 4: win(4, "L", "X-C")]
    }
    let laptopSpaces: [String: Set<String>] = ["L": ["primary", "L-3", "L-4", "X-B", "X-C"]]

    func testCollapsePutsExternalWindowsIntoTheirGroupsLaptopSpace() {
        let moves = WindowMovePlanner.planCollapse(snapshot: before, groups: groups, connected: ["L"],
                                                   spacesByDisplay: laptopSpaces, current: afterDisconnectCurrent)
        XCTAssertEqual(Set(moves.map { [$0.windowID: $0.to.spaceKey] }.map { $0.first! }.map { "\($0.key):\($0.value)" }),
                       ["1:L-3", "2:L-4"])
        XCTAssertEqual(moves.first { $0.windowID == 1 }?.from, loc("L", "primary"))
    }

    func testLaptopAndUngroupedWindowsAreLeftAlone() {
        let moves = WindowMovePlanner.planCollapse(snapshot: before, groups: groups, connected: ["L"],
                                                   spacesByDisplay: laptopSpaces, current: afterDisconnectCurrent)
        XCTAssertFalse(moves.contains { $0.windowID == 3 || $0.windowID == 4 })
    }

    func testNoRemovedDisplayMeansNoMoves() {
        XCTAssertEqual(WindowMovePlanner.planCollapse(snapshot: before, groups: groups, connected: ["L", "X"],
                                                      spacesByDisplay: laptopSpaces, current: afterDisconnectCurrent), [])
    }

    func testWindowThatNoLongerExistsIsSkipped() {
        var cur = afterDisconnectCurrent; cur[1] = nil
        let moves = WindowMovePlanner.planCollapse(snapshot: before, groups: groups, connected: ["L"],
                                                   spacesByDisplay: laptopSpaces, current: cur)
        XCTAssertEqual(moves.map(\.windowID), [2])
    }

    func testReusedWindowIDWithDifferentPIDIsSkipped() {
        var cur = afterDisconnectCurrent; cur[1] = win(1, "L", "primary", pid: 999)
        let moves = WindowMovePlanner.planCollapse(snapshot: before, groups: groups, connected: ["L"],
                                                   spacesByDisplay: laptopSpaces, current: cur)
        XCTAssertEqual(moves.map(\.windowID), [2])
    }

    func testAlreadyInTargetSpaceIsSkipped() {
        var cur = afterDisconnectCurrent; cur[1] = win(1, "L", "L-3")
        let moves = WindowMovePlanner.planCollapse(snapshot: before, groups: groups, connected: ["L"],
                                                   spacesByDisplay: laptopSpaces, current: cur)
        XCTAssertEqual(moves.map(\.windowID), [2])
    }

    func testTargetSpaceThatNoLongerExistsIsSkipped() {
        let spaces: [String: Set<String>] = ["L": ["primary", "L-4", "X-B"]]   // L-3 deleted
        let moves = WindowMovePlanner.planCollapse(snapshot: before, groups: groups, connected: ["L"],
                                                   spacesByDisplay: spaces, current: afterDisconnectCurrent)
        XCTAssertEqual(moves.map(\.windowID), [2])
    }

    func testDisplayPriorityPicksPreferredRemainingDisplay() {
        let g = [GroupSpec(id: UUID(), spaces: ["L": "L-3", "M": "M-1", "X": "X-A"])]
        let snap = WindowSnapshot(time: 1, displays: ["L", "M", "X"], windows: [win(1, "X", "X-A")], bootSession: 1)
        let spaces: [String: Set<String>] = ["L": ["primary", "L-3"], "M": ["M-1"]]
        let cur = [1: win(1, "L", "primary")]
        let preferM = WindowMovePlanner.planCollapse(snapshot: snap, groups: g, connected: ["L", "M"], spacesByDisplay: spaces,
                                                     current: cur, displayPriority: ["M"])
        XCTAssertEqual(preferM.first?.to, loc("M", "M-1"))
        let defaultPick = WindowMovePlanner.planCollapse(snapshot: snap, groups: g, connected: ["L", "M"], spacesByDisplay: spaces,
                                                         current: cur)
        XCTAssertEqual(defaultPick.first?.to, loc("L", "L-3"))   // alphabetical by display UUID
    }

    func testMovesAreOrderedForBatching() {
        let moves = WindowMovePlanner.planCollapse(snapshot: before, groups: groups, connected: ["L"],
                                                   spacesByDisplay: laptopSpaces, current: afterDisconnectCurrent)
        let keys = moves.map { "\($0.from.spaceKey)>\($0.to.spaceKey)" }
        XCTAssertEqual(keys, keys.sorted())
    }

    // MARK: restore

    func testRecordsCaptureOriginAndPlacement() {
        let moves = WindowMovePlanner.planCollapse(snapshot: before, groups: groups, connected: ["L"],
                                                   spacesByDisplay: laptopSpaces, current: afterDisconnectCurrent)
        let recs = WindowMovePlanner.records(for: moves, snapshot: before)
        XCTAssertEqual(recs.first { $0.windowID == 2 }, MovedRecord(windowID: 2, pid: 100, origin: loc("X", "X-B"), placedAt: loc("L", "L-4")))
    }

    func testRestoreMovesWindowsBackToOrigin() {
        let recs = [MovedRecord(windowID: 1, pid: 100, origin: loc("X", "X-A"), placedAt: loc("L", "L-3"))]
        let moves = WindowMovePlanner.planRestore(records: recs, connected: ["L", "X"],
                                                  spacesByDisplay: ["L": ["L-3"], "X": ["X-A", "X-B"]],
                                                  current: [1: win(1, "L", "L-3")])
        XCTAssertEqual(moves, [PlannedMove(windowID: 1, pid: 100, from: loc("L", "L-3"), to: loc("X", "X-A"))])
    }

    func testRestoreSkipsWindowTheUserMovedSince() {
        let recs = [MovedRecord(windowID: 1, pid: 100, origin: loc("X", "X-A"), placedAt: loc("L", "L-3"))]
        let moves = WindowMovePlanner.planRestore(records: recs, connected: ["L", "X"],
                                                  spacesByDisplay: ["L": ["L-3", "L-4"], "X": ["X-A"]],
                                                  current: [1: win(1, "L", "L-4")])
        XCTAssertEqual(moves, [])
    }

    func testRestoreSkipsWhenOriginDisplayStillAbsent() {
        let recs = [MovedRecord(windowID: 1, pid: 100, origin: loc("X", "X-A"), placedAt: loc("L", "L-3"))]
        XCTAssertEqual(WindowMovePlanner.planRestore(records: recs, connected: ["L"], spacesByDisplay: ["L": ["L-3"]],
                                                     current: [1: win(1, "L", "L-3")]), [])
    }

    func testRestoreSkipsMissingOriginSpaceAndGoneWindows() {
        let recs = [
            MovedRecord(windowID: 1, pid: 100, origin: loc("X", "X-A"), placedAt: loc("L", "L-3")),
            MovedRecord(windowID: 2, pid: 100, origin: loc("X", "X-B"), placedAt: loc("L", "L-4")),
        ]
        let moves = WindowMovePlanner.planRestore(records: recs, connected: ["L", "X"],
                                                  spacesByDisplay: ["L": ["L-3", "L-4"], "X": ["X-B"]],   // X-A gone
                                                  current: [1: win(1, "L", "L-3")])                       // window 2 gone
        XCTAssertEqual(moves, [])
    }

    func testRestoreSkipsWindowWithDifferentPID() {
        let recs = [MovedRecord(windowID: 1, pid: 100, origin: loc("X", "X-A"), placedAt: loc("L", "L-3"))]
        XCTAssertEqual(WindowMovePlanner.planRestore(records: recs, connected: ["L", "X"],
                                                     spacesByDisplay: ["L": ["L-3"], "X": ["X-A"]],
                                                     current: [1: win(1, "L", "L-3", pid: 7)]), [])
    }

    func testMovedRecordIsCodable() throws {
        let r = MovedRecord(windowID: 1, pid: 2, origin: loc("X", "a"), placedAt: loc("L", "b"))
        XCTAssertEqual(try JSONDecoder().decode(MovedRecord.self, from: JSONEncoder().encode(r)), r)
    }
}
