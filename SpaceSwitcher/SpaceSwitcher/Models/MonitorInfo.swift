import Foundation
import CoreGraphics

struct SpaceInfo: Hashable {
    let desktopNumber: Int   // Global desktop number (e.g. 5)
    let spaceID: UInt64      // Internal macOS space ID. NOT stable across display reconnects.
    let uuid: String         // Space UUID (stable); empty for a display's primary Space
}

struct MonitorInfo: Identifiable, Hashable {
    let id: String
    let displayID: CGDirectDisplayID
    let displayUUID: String  // Display UUID string for CGS APIs
    let frame: CGRect
    let label: String
    var spaces: [SpaceInfo] = []

    var desktopNumbers: [Int] { spaces.map(\.desktopNumber) }

    /// Per-monitor 1-based indices: [1, 2, 3, ...]
    var spaceIndices: [Int] { Array(1...max(spaces.count, 1)) }

    /// Look up a space by its per-monitor 1-based index.
    func spaceInfo(forIndex index: Int) -> SpaceInfo? {
        guard index >= 1, index <= spaces.count else { return nil }
        return spaces[index - 1]
    }
}
