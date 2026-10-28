import Foundation

/// The Space layout of all displays, parsed from `CGSCopyManagedDisplaySpaces`.
struct SpaceLayout: Equatable {
    /// Where each (user) Space currently lives, by CGS id64. Ids are not stable across reconnects; use only
    /// within one snapshot.
    var locationBySpaceID: [UInt64: WindowLocation] = [:]
    var displays: Set<String> = []
    /// Space keys that exist on each display right now.
    var spacesByDisplay: [String: Set<String>] = [:]

    /// Parses the array returned by `CGSCopyManagedDisplaySpaces`. Only regular desktop Spaces (type 0) are
    /// included; fullscreen Spaces and anything malformed are skipped.
    static func parse(_ managed: [[String: Any]]) -> SpaceLayout {
        var layout = SpaceLayout()
        for display in managed {
            guard let uuid = display["Display Identifier"] as? String, !uuid.isEmpty else { continue }
            layout.displays.insert(uuid)
            var keys: Set<String> = []
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard (space["type"] as? NSNumber)?.intValue == 0,
                      let id = (space["id64"] as? NSNumber)?.uint64Value else { continue }
                let key = SpaceIdentity.key(for: SpaceRef(id: id, uuid: space["uuid"] as? String ?? ""))
                layout.locationBySpaceID[id] = WindowLocation(displayUUID: uuid, spaceKey: key)
                keys.insert(key)
            }
            layout.spacesByDisplay[uuid] = keys
        }
        return layout
    }
}
