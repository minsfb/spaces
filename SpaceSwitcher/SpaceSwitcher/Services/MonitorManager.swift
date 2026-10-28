import AppKit
import CoreGraphics

struct DisplaySpaceData {
    let displayUUID: String
    let spaces: [SpaceInfo]
}

enum MonitorManager {
    /// Detect all connected monitors, sorted left-to-right by screen origin.
    static func detectMonitors() -> [MonitorInfo] {
        let screens = NSScreen.screens
        let sorted = screens.sorted { $0.frame.origin.x < $1.frame.origin.x }
        let spaceData = getSpaceDataPerDisplay()

        return sorted.enumerated().map { index, screen in
            let label: String
            if sorted.count == 1 {
                label = "Main"
            } else if index == 0 {
                label = "Left"
            } else if index == sorted.count - 1 {
                label = "Right"
            } else {
                label = "Center-\(index)"
            }

            let data = spaceData[screen.displayID]
            return MonitorInfo(
                id: label,
                displayID: screen.displayID,
                displayUUID: data?.displayUUID ?? "",
                frame: screen.cgFrame,
                label: label,
                spaces: data?.spaces ?? []
            )
        }
    }

    /// Query space IDs and global desktop numbers per display using private CGS API.
    private static func getSpaceDataPerDisplay() -> [CGDirectDisplayID: DisplaySpaceData] {
        let conn = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] else {
            return [:]
        }

        // Build a lookup from display UUID string → CGDirectDisplayID
        var uuidToDisplayID: [String: CGDirectDisplayID] = [:]
        for screen in NSScreen.screens {
            let displayID = screen.displayID
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) {
                let uuidStr = CFUUIDCreateString(nil, uuid.takeUnretainedValue()) as String
                uuidToDisplayID[uuidStr] = displayID
            }
        }

        // Collect space IDs and assign global desktop numbers
        var result: [CGDirectDisplayID: DisplaySpaceData] = [:]
        var globalIndex = 1
        for displayInfo in displays {
            guard let displayUUID = displayInfo["Display Identifier"] as? String,
                  let rawSpaces = displayInfo["Spaces"] as? [[String: Any]] else { continue }

            // Filter to regular desktop spaces (type 0), skip fullscreen (type 4)
            var spaceInfos: [SpaceInfo] = []
            for space in rawSpaces {
                guard (space["type"] as? Int) == 0,
                      let spaceID = space["id64"] as? UInt64 else { continue }
                spaceInfos.append(SpaceInfo(desktopNumber: globalIndex, spaceID: spaceID, uuid: space["uuid"] as? String ?? ""))
                globalIndex += 1
            }

            if let displayID = uuidToDisplayID[displayUUID] {
                result[displayID] = DisplaySpaceData(displayUUID: displayUUID, spaces: spaceInfos)
            }
        }

        return result
    }
}
