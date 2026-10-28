import Foundation

/// A group resolved to concrete Spaces: display UUID -> the Space (CGS id64) that group uses on it.
struct FollowGroup: Equatable {
    let id: UUID
    let targets: [String: UInt64]
}

/// Ask for `displayUUID` to be switched to `spaceID`.
struct SwitchRequest: Equatable {
    let displayUUID: String
    let spaceID: UInt64
}

/// Decides how other displays should follow when the user changes the Space on one display by a
/// native means (three-finger swipe, Ctrl+arrow, Mission Control).
///
/// Pure logic: feed it consecutive snapshots of current Spaces; it returns the switches to perform.
/// It remembers switches it requested (`pending`) so that the Space changes those cause are not
/// mistaken for user input (which would cause feedback loops / ping-pong).
struct GestureFollower {
    /// How long a requested switch is expected to take effect. After this, a matching change is
    /// treated as user input again.
    var pendingTTL: TimeInterval = 2.0

    private struct Pending { let spaceID: UInt64; let expires: TimeInterval }
    private var pending: [String: Pending] = [:]

    init(pendingTTL: TimeInterval = 2.0) { self.pendingTTL = pendingTTL }

    /// - Parameters:
    ///   - old/new: current Space per display before and after the notification.
    ///   - groups: all groups, resolved against the current monitors/Spaces.
    ///   - now: monotonic time in seconds (injectable for tests).
    /// - Returns: switches to perform on *other* displays so the whole group lines up.
    mutating func handle(old: CurrentSpaces, new: CurrentSpaces, groups: [FollowGroup], now: TimeInterval) -> [SwitchRequest] {
        pending = pending.filter { $0.value.expires > now }

        let changes = SpaceDiff.changedDisplays(old: old, new: new)
        guard !changes.isEmpty else { return [] }

        var userChanges: [SpaceDiff.Change] = []
        for change in changes {
            if let p = pending[change.displayUUID], p.spaceID == change.to {
                pending[change.displayUUID] = nil          // our own switch landed
            } else {
                pending[change.displayUUID] = nil          // user overrode any outstanding request
                userChanges.append(change)
            }
        }
        guard let trigger = userChanges.first else { return [] }
        pending.removeAll()   // a new user gesture supersedes any earlier, unfinished plan

        // First group (in the given order) that uses the new Space on the changed display.
        guard let group = groups.first(where: { $0.targets[trigger.displayUUID] == trigger.to }) else {
            return []                                       // Space is not part of any group
        }

        var requests: [SwitchRequest] = []
        for (uuid, target) in group.targets.sorted(by: { $0.key < $1.key }) where uuid != trigger.displayUUID {
            guard let current = new[uuid], current != target else { continue }   // absent display, or already aligned
            requests.append(SwitchRequest(displayUUID: uuid, spaceID: target))
            pending[uuid] = Pending(spaceID: target, expires: now + pendingTTL)
        }
        return requests
    }
}
