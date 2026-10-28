import Foundation

/// One Space of a display as reported by `CGSCopyManagedDisplaySpaces`.
/// `id` (id64) is NOT stable: it changed for a display's first Space across unplug/replug. `uuid` is stable,
/// except that a display's primary Space can have an empty uuid.
struct SpaceRef: Equatable {
    let id: UInt64
    let uuid: String
}

/// A currently-known monitor, for migrating legacy (label + index) group mappings.
struct LegacyMonitor: Equatable {
    let label: String          // position label, e.g. "Left"
    let displayUUID: String
    let spaces: [SpaceRef]     // ordered, user Spaces only
}

/// Stable identity for Spaces: groups remember `displayUUID -> spaceKey`, not Space IDs or positions.
enum SpaceIdentity {
    /// Key for a display's primary Space when macOS reports an empty uuid for it.
    static let primaryKey = "primary"

    static func key(for space: SpaceRef) -> String {
        space.uuid.isEmpty ? primaryKey : space.uuid
    }

    /// Key of the Space at a 1-based position within a display's ordered Spaces.
    static func key(atIndex index: Int, in spaces: [SpaceRef]) -> String? {
        guard index >= 1, index <= spaces.count else { return nil }
        return key(for: spaces[index - 1])
    }

    /// 1-based position of the Space with this key, or nil if that Space no longer exists.
    static func index(ofKey key: String, in spaces: [SpaceRef]) -> Int? {
        spaces.firstIndex(where: { self.key(for: $0) == key }).map { $0 + 1 }
    }
}

enum LegacyMigration {
    struct Result: Equatable {
        var displaySpaces: [String: String]   // displayUUID -> spaceKey
        var legacy: [String: Int]             // entries that could not be migrated yet
        var changed: Bool
    }

    /// Convert legacy `label -> 1-based index` entries into `displayUUID -> spaceKey` where the monitor is
    /// currently connected. Entries for monitors that are not connected stay in `legacy` to be migrated
    /// later. Entries whose index no longer exists on a connected monitor are dropped. Existing
    /// `displaySpaces` entries are never overwritten.
    static func migrate(legacy: [String: Int], displaySpaces: [String: String], monitors: [LegacyMonitor]) -> Result {
        var display = displaySpaces
        var remaining = legacy
        var changed = false
        for (label, index) in legacy.sorted(by: { $0.key < $1.key }) {
            guard let monitor = monitors.first(where: { $0.label == label }), !monitor.displayUUID.isEmpty else { continue }
            if display[monitor.displayUUID] == nil, let key = SpaceIdentity.key(atIndex: index, in: monitor.spaces) {
                display[monitor.displayUUID] = key
            }
            remaining[label] = nil
            changed = true
        }
        return Result(displaySpaces: display, legacy: remaining, changed: changed)
    }
}
