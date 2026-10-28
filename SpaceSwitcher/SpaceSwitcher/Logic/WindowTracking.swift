import Foundation

/// Where a window lives: a Space (by stable key, see `SpaceIdentity`) on a display (by UUID).
struct WindowLocation: Hashable, Codable {
    let displayUUID: String
    let spaceKey: String
}

/// A window we track. Identified by its live `CGWindowID` only (no titles): IDs are stable for a window's
/// lifetime, including across display disconnects, and do not survive reboot.
struct TrackedWindow: Equatable, Codable {
    let id: Int
    let pid: Int
    let location: WindowLocation
}

/// One periodic snapshot of every tracked window plus which displays were connected.
struct WindowSnapshot: Equatable, Codable {
    var time: TimeInterval
    var displays: Set<String>
    var windows: [TrackedWindow]
    /// Boot-session marker (e.g. boot time). Window IDs do not survive a reboot, so stored snapshots from
    /// another boot must be discarded.
    var bootSession: Double

    func isValid(forBootSession current: Double) -> Bool { bootSession == current }
}

/// Raw facts about a window as read from CoreGraphics, for deciding whether it is worth tracking.
struct RawWindow: Equatable {
    let id: Int
    let pid: Int
    let layer: Int
    let alpha: Double
    let width: Double
    let height: Double
    /// Number of Spaces the window belongs to (0 for windows not in any Space).
    let spaceCount: Int
}

enum WindowFilter {
    /// Real, user-visible application windows: normal layer, not transparent, not tiny helper windows, in at
    /// least one Space, and not one of our own windows.
    static func isTrackable(_ w: RawWindow, excludingPID ownPID: Int? = nil,
                            minWidth: Double = 100, minHeight: Double = 60) -> Bool {
        w.layer == 0 && w.alpha > 0 && w.width >= minWidth && w.height >= minHeight
            && w.spaceCount > 0 && w.pid != ownPID
    }
}

/// Recent snapshots, kept so that the state from *before* a display disconnect is still available after the
/// system has already moved the windows (the display-change callback is too late for a live read).
struct WindowSnapshotHistory {
    var capacity: Int
    private(set) var snapshots: [WindowSnapshot] = []
    private(set) var frozenAt: TimeInterval?

    init(capacity: Int = 10) { self.capacity = max(1, capacity) }

    /// Stop recording (call at the start of a display reconfiguration).
    mutating func freeze(at time: TimeInterval) { frozenAt = time }
    mutating func unfreeze() { frozenAt = nil }
    var isFrozen: Bool { frozenAt != nil }

    /// Add a snapshot. Ignored while frozen. A snapshot identical to the newest one (apart from time) only
    /// refreshes its time, so the history holds distinct states rather than N copies of the same one.
    mutating func record(_ s: WindowSnapshot) {
        guard frozenAt == nil else { return }
        if let last = snapshots.last, last.displays == s.displays, last.windows == s.windows,
           last.bootSession == s.bootSession {
            snapshots[snapshots.count - 1].time = s.time
            return
        }
        snapshots.append(s)
        if snapshots.count > capacity { snapshots.removeFirst(snapshots.count - capacity) }
    }

    /// Newest snapshot in which all `removed` displays were still connected (and, if frozen, taken no later
    /// than the freeze). This is the "before disconnect" state.
    func snapshotBeforeDisconnect(of removed: Set<String>) -> WindowSnapshot? {
        snapshots.last { s in
            removed.isSubset(of: s.displays) && (frozenAt.map { s.time <= $0 } ?? true)
        }
    }
}
