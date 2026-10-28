import XCTest
@testable import SpaceLogic

final class WindowTrackingTests: XCTestCase {
    func loc(_ d: String, _ k: String) -> WindowLocation { WindowLocation(displayUUID: d, spaceKey: k) }
    func win(_ id: Int, _ d: String, _ k: String, pid: Int = 100) -> TrackedWindow { TrackedWindow(id: id, pid: pid, location: loc(d, k)) }
    func snap(_ t: TimeInterval, displays: Set<String> = ["L", "X"], _ windows: [TrackedWindow], boot: Double = 1) -> WindowSnapshot {
        WindowSnapshot(time: t, displays: displays, windows: windows, bootSession: boot)
    }

    // MARK: filter

    func raw(layer: Int = 0, alpha: Double = 1, w: Double = 800, h: Double = 600, spaces: Int = 1, pid: Int = 5) -> RawWindow {
        RawWindow(id: 1, pid: pid, layer: layer, alpha: alpha, width: w, height: h, spaceCount: spaces)
    }

    func testFilterAcceptsNormalWindow() { XCTAssertTrue(WindowFilter.isTrackable(raw())) }
    func testFilterRejectsOtherLayers() { XCTAssertFalse(WindowFilter.isTrackable(raw(layer: 25))) }
    func testFilterRejectsInvisible() { XCTAssertFalse(WindowFilter.isTrackable(raw(alpha: 0))) }
    func testFilterRejectsTinyWindows() {
        XCTAssertFalse(WindowFilter.isTrackable(raw(w: 50)))
        XCTAssertFalse(WindowFilter.isTrackable(raw(h: 20)))
    }
    func testFilterRejectsWindowsInNoSpace() { XCTAssertFalse(WindowFilter.isTrackable(raw(spaces: 0))) }
    func testFilterRejectsOwnWindows() { XCTAssertFalse(WindowFilter.isTrackable(raw(pid: 42), excludingPID: 42)) }

    // MARK: history

    func testHistoryDedupesIdenticalStates() {
        var h = WindowSnapshotHistory(capacity: 5)
        let ws = [win(1, "L", "a")]
        h.record(snap(1, ws)); h.record(snap(2, ws)); h.record(snap(3, ws))
        XCTAssertEqual(h.snapshots.count, 1)
        XCTAssertEqual(h.snapshots[0].time, 3)
    }

    func testHistoryKeepsDistinctStatesUpToCapacity() {
        var h = WindowSnapshotHistory(capacity: 3)
        for i in 1...5 { h.record(snap(TimeInterval(i), [win(i, "L", "a")])) }
        XCTAssertEqual(h.snapshots.map(\.time), [3, 4, 5])
    }

    func testFreezeStopsRecording() {
        var h = WindowSnapshotHistory()
        h.record(snap(1, [win(1, "L", "a")]))
        h.freeze(at: 2)
        h.record(snap(3, [win(1, "L", "b")]))
        XCTAssertEqual(h.snapshots.count, 1)
        h.unfreeze()
        h.record(snap(4, [win(1, "L", "b")]))
        XCTAssertEqual(h.snapshots.count, 2)
    }

    func testSnapshotBeforeDisconnectPicksNewestWithDisplayPresent() {
        var h = WindowSnapshotHistory()
        h.record(snap(1, [win(1, "X", "a")]))
        h.record(snap(2, [win(1, "X", "b")]))
        h.record(snap(3, displays: ["L"], [win(1, "L", "primary")]))     // already collapsed
        XCTAssertEqual(h.snapshotBeforeDisconnect(of: ["X"])?.time, 2)
    }

    func testSnapshotBeforeDisconnectRespectsFreezeTime() {
        var h = WindowSnapshotHistory()
        h.record(snap(1, [win(1, "X", "a")]))
        h.record(snap(5, [win(1, "X", "b")]))
        h.freeze(at: 3)
        XCTAssertEqual(h.snapshotBeforeDisconnect(of: ["X"])?.time, 1)
    }

    func testSnapshotBeforeDisconnectNoneAvailable() {
        var h = WindowSnapshotHistory()
        h.record(snap(1, displays: ["L"], [win(1, "L", "a")]))
        XCTAssertNil(h.snapshotBeforeDisconnect(of: ["X"]))
    }

    func testBootSessionValidity() {
        XCTAssertTrue(snap(1, [], boot: 7).isValid(forBootSession: 7))
        XCTAssertFalse(snap(1, [], boot: 7).isValid(forBootSession: 8))
    }

    func testSnapshotIsCodable() throws {
        let s = snap(1, [win(1, "X", "k")], boot: 9)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(WindowSnapshot.self, from: data), s)
    }
}
