import AppKit
import CoreGraphics

/// Read-only capture of where every trackable window currently lives. Records window IDs only, never titles.
enum WindowSnapshotter {
    static func currentLayout() -> SpaceLayout {
        SpaceLayout.parse(CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? [])
    }

    /// Seconds since the epoch at which the system booted; window IDs do not survive a reboot.
    static func bootSession() -> Double {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return 0 }
        return Double(tv.tv_sec)
    }

    /// Windows in exactly one regular Space (windows shown on all desktops are skipped).
    static func capture(layout: SpaceLayout, now: TimeInterval) -> WindowSnapshot {
        let conn = CGSMainConnectionID()
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        let list = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var windows: [TrackedWindow] = []
        for info in list {
            guard let id = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let spaces = (CGSCopySpacesForWindows(conn, 7, [id] as CFArray) as? [Int]) ?? []
            let raw = RawWindow(id: id, pid: pid, layer: layer,
                                alpha: info[kCGWindowAlpha as String] as? Double ?? 1,
                                width: Double(bounds["Width"] ?? 0), height: Double(bounds["Height"] ?? 0),
                                spaceCount: spaces.count)
            guard WindowFilter.isTrackable(raw, excludingPID: ownPID), spaces.count == 1,
                  let location = layout.locationBySpaceID[UInt64(spaces[0])] else { continue }
            windows.append(TrackedWindow(id: id, pid: pid, location: location))
        }
        windows.sort { $0.id < $1.id }
        return WindowSnapshot(time: now, displays: layout.displays, windows: windows, bootSession: bootSession())
    }

    static func windowsByID(_ snapshot: WindowSnapshot) -> [Int: TrackedWindow] {
        Dictionary(snapshot.windows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
}
