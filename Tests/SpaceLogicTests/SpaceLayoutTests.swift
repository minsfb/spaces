import XCTest
@testable import SpaceLogic

final class SpaceLayoutTests: XCTestCase {
    // Shape taken from real CGSCopyManagedDisplaySpaces output (ids/uuids synthetic).
    let sample: [[String: Any]] = [
        ["Display Identifier": "DISP-L",
         "Current Space": ["id64": 3],
         "Spaces": [
            ["id64": 1, "type": 0, "uuid": ""],
            ["id64": 3, "type": 0, "uuid": "L-3"],
            ["id64": 50, "type": 4, "uuid": "FS-1"],      // fullscreen Space
         ]],
        ["Display Identifier": "DISP-X",
         "Spaces": [["id64": 1039, "type": 0, "uuid": "X-A"], ["id64": 1030, "type": 0, "uuid": "X-B"]]],
    ]

    func testParsesDisplaysAndSpaces() {
        let l = SpaceLayout.parse(sample)
        XCTAssertEqual(l.displays, ["DISP-L", "DISP-X"])
        XCTAssertEqual(l.spacesByDisplay["DISP-L"], ["primary", "L-3"])
        XCTAssertEqual(l.spacesByDisplay["DISP-X"], ["X-A", "X-B"])
    }

    func testMapsSpaceIDsToLocations() {
        let l = SpaceLayout.parse(sample)
        XCTAssertEqual(l.locationBySpaceID[1], WindowLocation(displayUUID: "DISP-L", spaceKey: "primary"))
        XCTAssertEqual(l.locationBySpaceID[1039], WindowLocation(displayUUID: "DISP-X", spaceKey: "X-A"))
    }

    func testSkipsFullscreenSpaces() {
        XCTAssertNil(SpaceLayout.parse(sample).locationBySpaceID[50])
    }

    func testSkipsMalformedEntries() {
        let l = SpaceLayout.parse([["Spaces": []], ["Display Identifier": "", "Spaces": []],
                                   ["Display Identifier": "D", "Spaces": [["type": 0], ["id64": 5, "type": 0, "uuid": "u"]]]])
        XCTAssertEqual(l.displays, ["D"])
        XCTAssertEqual(l.spacesByDisplay["D"], ["u"])
    }

    func testEmptyInput() { XCTAssertEqual(SpaceLayout.parse([]), SpaceLayout()) }

    func testExternalSpacesAppendedToLaptopWhileDisconnected() {
        let l = SpaceLayout.parse([["Display Identifier": "DISP-L", "Spaces": [
            ["id64": 1, "type": 0, "uuid": ""], ["id64": 1030, "type": 0, "uuid": "X-B"]]]])
        XCTAssertEqual(l.locationBySpaceID[1030], WindowLocation(displayUUID: "DISP-L", spaceKey: "X-B"))
    }
}
