import AppKit
import SwiftUI

@Observable
final class AppState {
    var groups: [DesktopGroup] = []
    var monitors: [MonitorInfo] = []
    var activeGroupID: UUID?
    var pendingSelectGroupID: UUID?

    /// When on, changing the Space on one display by any native means (e.g. three-finger swipe) moves the
    /// other displays to the same group's Spaces. Off by default.
    var followEnabled: Bool = UserDefaults.standard.bool(forKey: "gestureFollowEnabled") {
        didSet { UserDefaults.standard.set(followEnabled, forKey: "gestureFollowEnabled") }
    }

    private var follower = GestureFollower()
    private var lastCurrentSpaces: CurrentSpaces = [:]
    private let persistence = PersistenceManager()

    init() {
        // Older saved groups first go global-desktop-number -> per-monitor index (PersistenceManager),
        // then per-monitor index -> Space UUID keys (refreshMonitors).
        monitors = MonitorManager.detectMonitors()
        persistence.migrateToPerMonitorIndicesIfNeeded(monitors: monitors)
        groups = persistence.loadGroups()
        refreshMonitors()
        lastCurrentSpaces = SpaceSwitcherService.getCurrentSpacePerDisplay()
        detectActiveGroup()

        // Re-detect active group whenever the user switches spaces (e.g. via Mission Control)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func spaceDidChange() {
        let old = lastCurrentSpaces
        let new = SpaceSwitcherService.getCurrentSpacePerDisplay()
        lastCurrentSpaces = new
        refreshMonitors()
        detectActiveGroup()

        guard followEnabled else { return }
        let requests = follower.handle(
            old: old, new: new,
            groups: followGroups(),
            now: ProcessInfo.processInfo.systemUptime
        )
        guard !requests.isEmpty else { return }
        let monitorsCopy = monitors
        Task { @MainActor in
            await SpaceSwitcherService.switchDisplays(requests, monitors: monitorsCopy)
        }
    }

    /// Resolve saved groups (display UUID -> Space key) to concrete display UUID -> current Space ID.
    private func followGroups() -> [FollowGroup] {
        groups.compactMap { group in
            var targets: [String: UInt64] = [:]
            for monitor in monitors {
                if let space = group.space(on: monitor) { targets[monitor.displayUUID] = space.spaceID }
            }
            return targets.isEmpty ? nil : FollowGroup(id: group.id, targets: targets)
        }
    }

    func refreshMonitors() {
        monitors = MonitorManager.detectMonitors()
        migrateLegacyGroups()
    }

    /// Convert legacy (monitor label + index) group entries to Space-UUID keys for monitors that are connected now.
    /// Groups keyed by UUID need no reconciliation when Spaces are added, removed, reordered or re-created.
    private func migrateLegacyGroups() {
        let legacyMonitors = monitors.map {
            LegacyMonitor(label: $0.id, displayUUID: $0.displayUUID,
                          spaces: $0.spaces.map { SpaceRef(id: $0.spaceID, uuid: $0.uuid) })
        }
        var anyChanged = false
        for i in groups.indices where !groups[i].monitorSpaces.isEmpty {
            let r = LegacyMigration.migrate(legacy: groups[i].monitorSpaces,
                                            displaySpaces: groups[i].displaySpaces,
                                            monitors: legacyMonitors)
            guard r.changed else { continue }
            groups[i].displaySpaces = r.displaySpaces
            groups[i].monitorSpaces = r.legacy
            anyChanged = true
        }
        if anyChanged { saveGroups() }
    }

    func saveGroups() {
        persistence.saveGroups(groups)
    }

    func addGroup(_ group: DesktopGroup) {
        groups.append(group)
        saveGroups()
    }

    func deleteGroup(_ group: DesktopGroup) {
        groups.removeAll { $0.id == group.id }
        saveGroups()
    }

    func updateGroup(_ group: DesktopGroup) {
        if let idx = groups.firstIndex(where: { $0.id == group.id }) {
            groups[idx] = group
            saveGroups()
        }
    }

    func switchToGroup(_ group: DesktopGroup) {
        activeGroupID = group.id
        let groupCopy = group
        let monitorsCopy = monitors
        Task { @MainActor in
            await SpaceSwitcherService.switchToGroup(groupCopy, monitors: monitorsCopy)
        }
    }

    /// Detect which group (if any) matches the currently active spaces on all monitors.
    func detectActiveGroup() {
        let currentSpaces = SpaceSwitcherService.getCurrentSpacePerDisplay()

        for group in groups {
            let allMatch = monitors.allSatisfy { monitor in
                guard let spaceInfo = group.space(on: monitor),
                      let currentSpaceID = currentSpaces[monitor.displayUUID]
                else {
                    // If the group doesn't define a space for this monitor, skip it
                    return !group.hasSpace(on: monitor)
                }
                return spaceInfo.spaceID == currentSpaceID
            }

            if allMatch {
                activeGroupID = group.id
                return
            }
        }

        activeGroupID = nil
    }
}
