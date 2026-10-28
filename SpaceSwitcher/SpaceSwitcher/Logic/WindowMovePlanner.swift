import Foundation

/// A group's Spaces as stable keys: display UUID -> Space key (same shape as `DesktopGroup.displaySpaces`).
struct GroupSpec: Equatable {
    let id: UUID
    let spaces: [String: String]
}

struct PlannedMove: Equatable {
    let windowID: Int
    let pid: Int
    let from: WindowLocation
    let to: WindowLocation
}

/// Remembers a window we moved so it can be put back when its display returns.
struct MovedRecord: Equatable, Codable {
    let windowID: Int
    let pid: Int
    let origin: WindowLocation      // where the window lived before we moved it
    let placedAt: WindowLocation    // where we put it
}

/// Pure planning of window moves around a display disconnect/reconnect. Produces plans only; carrying them
/// out (emulated drag + Space switch, Accessibility) is separate and not part of this type.
enum WindowMovePlanner {
    /// After `removed` displays disappeared, plan moves of their windows into the *same group's* Space on a
    /// remaining display.
    ///
    /// - snapshot: state from before the disconnect (windows' original locations).
    /// - groups: group definitions.
    /// - connected: displays connected now.
    /// - spacesByDisplay: Space keys that exist on each connected display now (macOS may append the removed
    ///   display's extra Spaces to a remaining display while disconnected).
    /// - current: where each window is now (by window ID); windows missing here have gone away.
    /// - displayPriority: which remaining display to prefer when a group has Spaces on several (first wins).
    static func planCollapse(snapshot: WindowSnapshot,
                             groups: [GroupSpec],
                             connected: Set<String>,
                             spacesByDisplay: [String: Set<String>],
                             current: [Int: TrackedWindow],
                             displayPriority: [String] = []) -> [PlannedMove] {
        let removed = snapshot.displays.subtracting(connected)
        guard !removed.isEmpty else { return [] }

        var moves: [PlannedMove] = []
        for w in snapshot.windows where removed.contains(w.location.displayUUID) {
            guard let now = current[w.id], now.pid == w.pid else { continue }          // gone, or ID reused
            guard let group = groups.first(where: { $0.spaces[w.location.displayUUID] == w.location.spaceKey }) else { continue }

            let candidates = group.spaces
                .filter { connected.contains($0.key) && (spacesByDisplay[$0.key]?.contains($0.value) ?? false) }
                .map { WindowLocation(displayUUID: $0.key, spaceKey: $0.value) }
            guard let target = pick(candidates, priority: displayPriority) else { continue }
            guard now.location != target else { continue }                              // already there
            moves.append(PlannedMove(windowID: w.id, pid: w.pid, from: now.location, to: target))
        }
        // Group moves by source then target so an executor can batch work per Space.
        return moves.sorted {
            ($0.from.spaceKey, $0.to.spaceKey, $0.windowID) < ($1.from.spaceKey, $1.to.spaceKey, $1.windowID)
        }
    }

    /// Records for the planned moves, to persist so the windows can be restored later.
    static func records(for moves: [PlannedMove], snapshot: WindowSnapshot) -> [MovedRecord] {
        let origin = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.id, $0.location) })
        return moves.compactMap { m in
            origin[m.windowID].map { MovedRecord(windowID: m.windowID, pid: m.pid, origin: $0, placedAt: m.to) }
        }
    }

    /// When displays return, plan moves putting previously moved windows back to their origin. Only windows
    /// that still exist and are still where we put them are moved: a window the user has moved since is left
    /// alone, and an origin Space that no longer exists is skipped.
    static func planRestore(records: [MovedRecord],
                            connected: Set<String>,
                            spacesByDisplay: [String: Set<String>],
                            current: [Int: TrackedWindow]) -> [PlannedMove] {
        records.compactMap { r in
            guard connected.contains(r.origin.displayUUID),
                  spacesByDisplay[r.origin.displayUUID]?.contains(r.origin.spaceKey) == true,
                  let now = current[r.windowID], now.pid == r.pid,
                  now.location == r.placedAt,
                  now.location != r.origin else { return nil }
            return PlannedMove(windowID: r.windowID, pid: r.pid, from: now.location, to: r.origin)
        }
        .sorted { ($0.from.spaceKey, $0.to.spaceKey, $0.windowID) < ($1.from.spaceKey, $1.to.spaceKey, $1.windowID) }
    }

    private static func pick(_ candidates: [WindowLocation], priority: [String]) -> WindowLocation? {
        for uuid in priority { if let c = candidates.first(where: { $0.displayUUID == uuid }) { return c } }
        return candidates.sorted { $0.displayUUID < $1.displayUUID }.first
    }
}
