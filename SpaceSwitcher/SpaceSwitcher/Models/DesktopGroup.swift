import Foundation
import SwiftUI

struct DesktopGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var icon: String       // Icon asset name
    var colorName: String  // Unused legacy field, kept for decoding compatibility
    /// display UUID → Space key (see `SpaceIdentity`). Stable across unplug/replug, Space reordering and
    /// Space insertion, unlike Space IDs and per-monitor positions.
    var displaySpaces: [String: String]
    /// LEGACY: position label → 1-based index ("Left" → 3). Only kept so older saved groups can be decoded and
    /// migrated into `displaySpaces`; entries are removed as they are migrated.
    var monitorSpaces: [String: Int]

    init(id: UUID = UUID(), name: String, icon: String = "Labtop",
         colorName: String = "blue", displaySpaces: [String: String] = [:], monitorSpaces: [String: Int] = [:]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorName = colorName
        self.displaySpaces = displaySpaces
        self.monitorSpaces = monitorSpaces
    }

    // Older saved groups have no `displaySpaces`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decode(String.self, forKey: .icon)
        colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? "blue"
        displaySpaces = try c.decodeIfPresent([String: String].self, forKey: .displaySpaces) ?? [:]
        monitorSpaces = try c.decodeIfPresent([String: Int].self, forKey: .monitorSpaces) ?? [:]
    }

    // MARK: - Resolving against the current monitors

    private static func refs(_ monitor: MonitorInfo) -> [SpaceRef] {
        monitor.spaces.map { SpaceRef(id: $0.spaceID, uuid: $0.uuid) }
    }

    /// 1-based position of this group's Space on `monitor`, or nil if the group has none there or it no longer exists.
    func spaceIndex(on monitor: MonitorInfo) -> Int? {
        guard !monitor.displayUUID.isEmpty, let key = displaySpaces[monitor.displayUUID] else { return nil }
        return SpaceIdentity.index(ofKey: key, in: Self.refs(monitor))
    }

    /// This group's Space on `monitor`, resolved through the Space UUID.
    func space(on monitor: MonitorInfo) -> SpaceInfo? {
        spaceIndex(on: monitor).flatMap { monitor.spaceInfo(forIndex: $0) }
    }

    /// Whether the group defines a Space for this display at all (even if it no longer resolves).
    func hasSpace(on monitor: MonitorInfo) -> Bool {
        !monitor.displayUUID.isEmpty && displaySpaces[monitor.displayUUID] != nil
    }

    mutating func setSpaceIndex(_ index: Int, on monitor: MonitorInfo) {
        guard !monitor.displayUUID.isEmpty,
              let key = SpaceIdentity.key(atIndex: index, in: Self.refs(monitor)) else { return }
        displaySpaces[monitor.displayUUID] = key
    }

    /// Default mapping for a new group: the Space currently showing on each display.
    static func displaySpacesForCurrent(monitors: [MonitorInfo], currentSpaces: [String: UInt64]) -> [String: String] {
        var result: [String: String] = [:]
        for monitor in monitors where !monitor.displayUUID.isEmpty {
            let refs = Self.refs(monitor)
            let index = monitor.spaces.firstIndex(where: { $0.spaceID == currentSpaces[monitor.displayUUID] }).map { $0 + 1 } ?? 1
            if let key = SpaceIdentity.key(atIndex: index, in: refs) { result[monitor.displayUUID] = key }
        }
        return result
    }

    /// Pick a random icon.
    static func randomAppearance() -> (icon: String, color: String) {
        let icon = availableIcons.randomElement() ?? "Labtop"
        return (icon, "blue")
    }

    // MARK: - Available Icons

    static let availableIcons = [
        "3d",
        "Add-Device",
        "Airport-Railroad",
        "Android-Setting",
        "App-Window",
        "Astrology-Study",
        "Baby",
        "Baby-Cart-Quality",
        "Backpack",
        "Balloon-Tour",
        "Bigben",
        "Bluetooth",
        "Boarding-Pass",
        "Book-Library",
        "Bug",
        "Bus-Route-Info",
        "Cancel-2",
        "Candy-Cane",
        "Checking-Order",
        "Cloud-Data-Transfer",
        "Coding",
        "Compass-1",
        "Construction-Area",
        "Control",
        "Cursor",
        "Dangerous-Chemical-Lab",
        "Date-Time-Setting",
        "Drawer-Inbox",
        "Drone",
        "Earpod-Connected",
        "Easter-Egg",
        "Education-Degree",
        "Eiffel-Tower",
        "Elevator-Lift",
        "Face-Id-1",
        "Filming-Movie",
        "Ghost",
        "Gift-Reciept",
        "Globe-1",
        "Graph-Bar",
        "Graph-Pie",
        "Guitar-Amplifier",
        "Help",
        "Information-Toilet-Location",
        "Instruments-Piano",
        "Key",
        "Keyboard-Direction",
        "Lab-Tools",
        "Labtop",
        "Library-Research",
        "Love",
        "Mail",
        "Mailbox-2",
        "Medal",
        "Mobile-Phone",
        "Money-Briefcase",
        "Money-Coin-2",
        "Muslim",
        "Nuclear-2",
        "On-Off-1",
        "Online-Information",
        "Passport",
        "Pen",
        "Photography",
        "Picture",
        "Pile-Of-Money",
        "Plant-1",
        "Product-Cloth",
        "Programming",
        "Qr-Code",
        "Reciept-1",
        "Recycle",
        "Refund-Product-Reciept",
        "Reward",
        "Rocket-Launch-Chart",
        "Sad-Song",
        "Safety",
        "School",
        "Science-Lab",
        "Search",
        "Sent-From-Computer",
        "Server-Network",
        "Shop-Store",
        "Slate",
        "Smart-Tv",
        "Snowman",
        "Solar-Power-Battery",
        "Star",
        "Sun",
        "Sun-Clound-Weather",
        "Taxi",
        "Telescope",
        "Time",
        "Validation-1",
        "View-Mail",
        "Vr-Goggle",
        "Wand",
        "Winter-Day-Activities",
        "World-Nature",
        "Wrench",
    ]
}
