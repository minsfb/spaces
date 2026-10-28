import XCTest
@testable import SpaceLogic

final class SpaceIdentityTests: XCTestCase {
    // Laptop: first Space has an empty uuid (primary). External: all have uuids.
    let laptop = [SpaceRef(id: 1, uuid: ""), SpaceRef(id: 3, uuid: "L-3"), SpaceRef(id: 4, uuid: "L-4")]
    let external = [SpaceRef(id: 1026, uuid: "X-A"), SpaceRef(id: 1030, uuid: "X-B"), SpaceRef(id: 1031, uuid: "X-C")]

    func testKeyUsesUUIDOrPrimary() {
        XCTAssertEqual(SpaceIdentity.key(for: laptop[0]), "primary")
        XCTAssertEqual(SpaceIdentity.key(for: laptop[1]), "L-3")
    }

    func testKeyAtIndexAndBack() {
        XCTAssertEqual(SpaceIdentity.key(atIndex: 2, in: external), "X-B")
        XCTAssertEqual(SpaceIdentity.index(ofKey: "X-B", in: external), 2)
        XCTAssertEqual(SpaceIdentity.index(ofKey: "primary", in: laptop), 1)
    }

    func testIndexBoundsAndMissing() {
        XCTAssertNil(SpaceIdentity.key(atIndex: 0, in: external))
        XCTAssertNil(SpaceIdentity.key(atIndex: 4, in: external))
        XCTAssertNil(SpaceIdentity.index(ofKey: "gone", in: external))
        XCTAssertNil(SpaceIdentity.index(ofKey: "primary", in: external))   // external has no empty-uuid Space
    }

    func testResolvesAfterReorder() {
        let key = SpaceIdentity.key(atIndex: 3, in: laptop)!          // "L-4"
        let reordered = [laptop[2], laptop[0], laptop[1]]
        XCTAssertEqual(SpaceIdentity.index(ofKey: key, in: reordered), 1)
    }

    func testResolvesAfterSpaceInsertedBefore() {
        let key = SpaceIdentity.key(atIndex: 2, in: laptop)!           // "L-3"
        let withNew = [laptop[0], SpaceRef(id: 99, uuid: "new"), laptop[1], laptop[2]]
        XCTAssertEqual(SpaceIdentity.index(ofKey: key, in: withNew), 3)
    }

    func testResolvesAfterIdChangesButUUIDStays() {
        // Observed: the external's first Space id changed (989 -> 1026 -> 1039) while its uuid stayed.
        let key = SpaceIdentity.key(atIndex: 1, in: external)!
        let afterReplug = [SpaceRef(id: 1039, uuid: "X-A"), external[1], external[2]]
        XCTAssertEqual(SpaceIdentity.index(ofKey: key, in: afterReplug), 1)
        XCTAssertEqual(afterReplug[SpaceIdentity.index(ofKey: key, in: afterReplug)! - 1].id, 1039)
    }

    func testResolvesWhenExternalSpacesAreAppendedToLaptopWhileDisconnected() {
        // While unplugged macOS appended the external's extra Spaces to the laptop's list.
        let key = SpaceIdentity.key(atIndex: 2, in: external)!         // "X-B"
        let laptopWithAppended = laptop + [external[1], external[2]]
        XCTAssertEqual(SpaceIdentity.index(ofKey: key, in: laptopWithAppended), 4)
    }

    func testDeletedSpaceDoesNotResolve() {
        let key = SpaceIdentity.key(atIndex: 2, in: laptop)!
        XCTAssertNil(SpaceIdentity.index(ofKey: key, in: [laptop[0], laptop[2]]))
    }

    // MARK: legacy migration

    var monitors: [LegacyMonitor] {
        [
            LegacyMonitor(label: "Left", displayUUID: "DISP-L", spaces: [SpaceRef(id: 1, uuid: ""), SpaceRef(id: 3, uuid: "L-3")]),
            LegacyMonitor(label: "Right", displayUUID: "DISP-X", spaces: external),
        ]
    }

    func testMigratesConnectedMonitors() {
        let r = LegacyMigration.migrate(legacy: ["Left": 2, "Right": 3], displaySpaces: [:], monitors: monitors)
        XCTAssertEqual(r.displaySpaces, ["DISP-L": "L-3", "DISP-X": "X-C"])
        XCTAssertEqual(r.legacy, [:])
        XCTAssertTrue(r.changed)
    }

    func testPrimarySpaceMigratesToPrimaryKey() {
        let r = LegacyMigration.migrate(legacy: ["Left": 1], displaySpaces: [:], monitors: monitors)
        XCTAssertEqual(r.displaySpaces, ["DISP-L": "primary"])
    }

    func testDisconnectedMonitorStaysLegacy() {
        let r = LegacyMigration.migrate(legacy: ["Left": 2, "Right": 1], displaySpaces: [:], monitors: [monitors[0]])
        XCTAssertEqual(r.displaySpaces, ["DISP-L": "L-3"])
        XCTAssertEqual(r.legacy, ["Right": 1])
        XCTAssertTrue(r.changed)
    }

    func testOutOfRangeIndexOnConnectedMonitorIsDropped() {
        let r = LegacyMigration.migrate(legacy: ["Left": 9], displaySpaces: [:], monitors: monitors)
        XCTAssertEqual(r.displaySpaces, [:])
        XCTAssertEqual(r.legacy, [:])
        XCTAssertTrue(r.changed)
    }

    func testExistingEntriesAreNotOverwritten() {
        let r = LegacyMigration.migrate(legacy: ["Left": 2], displaySpaces: ["DISP-L": "primary"], monitors: monitors)
        XCTAssertEqual(r.displaySpaces, ["DISP-L": "primary"])
        XCTAssertEqual(r.legacy, [:])
    }

    func testNothingToDoIsNotChanged() {
        let r = LegacyMigration.migrate(legacy: [:], displaySpaces: ["DISP-L": "L-3"], monitors: monitors)
        XCTAssertFalse(r.changed)
        XCTAssertEqual(r.displaySpaces, ["DISP-L": "L-3"])
    }

    func testMonitorWithoutDisplayUUIDStaysLegacy() {
        let m = [LegacyMonitor(label: "Left", displayUUID: "", spaces: laptop)]
        let r = LegacyMigration.migrate(legacy: ["Left": 1], displaySpaces: [:], monitors: m)
        XCTAssertEqual(r.legacy, ["Left": 1])
        XCTAssertFalse(r.changed)
    }
}
