import Foundation

/// The current Space (CGS `id64`) of each display, keyed by display UUID string.
typealias CurrentSpaces = [String: UInt64]

enum SpaceDiff {
    struct Change: Equatable {
        let displayUUID: String
        let from: UInt64
        let to: UInt64
    }

    /// Displays present in *both* snapshots whose current Space differs.
    ///
    /// `NSWorkspace.activeSpaceDidChangeNotification` carries no display information, so callers
    /// compare consecutive snapshots of `getCurrentSpacePerDisplay()` to learn which display moved.
    /// Displays that appear or disappear (hot-plug) are not "changes" here. Result is sorted by
    /// display UUID so behaviour is deterministic.
    static func changedDisplays(old: CurrentSpaces, new: CurrentSpaces) -> [Change] {
        new.keys.sorted().compactMap { uuid in
            guard let from = old[uuid], let to = new[uuid], from != to else { return nil }
            return Change(displayUUID: uuid, from: from, to: to)
        }
    }
}
