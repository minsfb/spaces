import AppKit
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.spaceswitcher", category: "WindowTracker")

/// Keeps a short history of window/Space snapshots and, when a display is connected or disconnected, plans (but
/// does NOT perform) the window moves that would collapse/restore a group's windows. Experimental, dry-run only:
/// it logs counts and Space keys, never window titles, and moves nothing.
///
/// Snapshots are taken on a timer (default 30 s, configurable) because the display-change callback fires too late
/// for a live read: by then the system has already moved the windows.
/// All mutable state is read and written on the main thread only (background work just captures and hops back).
final class WindowTracker: @unchecked Sendable {
    /// Group definitions to plan against (display UUID -> Space key).
    var groupsProvider: () -> [GroupSpec] = { [] }

    private var history = WindowSnapshotHistory(capacity: 10)
    private var movedRecords: [MovedRecord] = []
    private var timer: Timer?
    private var registered = false
    private let queue = DispatchQueue(label: "com.spaceswitcher.windowtracker", qos: .utility)

    private(set) var interval: TimeInterval = 30

    var isRunning: Bool { timer != nil }

    func start(interval: TimeInterval) {
        stop()
        self.interval = max(1, interval)
        registerDisplayCallbackIfNeeded()
        captureNow()
        timer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { [weak self] _ in self?.captureNow() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        history = WindowSnapshotHistory(capacity: 10)
        movedRecords = []
    }

    private func captureNow() {
        guard !history.isFrozen else { return }
        queue.async { [weak self] in
            let layout = WindowSnapshotter.currentLayout()
            let snap = WindowSnapshotter.capture(layout: layout, now: ProcessInfo.processInfo.systemUptime)
            DispatchQueue.main.async { self?.history.record(snap) }
        }
    }

    // MARK: display reconfiguration

    private func registerDisplayCallbackIfNeeded() {
        guard !registered else { return }
        registered = true
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard let userInfo else { return }
            let tracker = Unmanaged<WindowTracker>.fromOpaque(userInfo).takeUnretainedValue()
            if flags.contains(.beginConfigurationFlag) {
                DispatchQueue.main.async { tracker.beginReconfiguration() }
            } else {
                DispatchQueue.main.async { tracker.endReconfiguration() }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    private var settleWork: DispatchWorkItem?

    /// Dry-run report written locally so the plan can be reviewed without Console access. Contains window IDs,
    /// app names and Space keys only (never window titles). Overwritten on each display change.
    static let reportURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SpaceSwitcher/dry-run.log")

    private func writeReport(_ lines: [String]) {
        let url = Self.reportURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let header = "SpaceSwitcher dry run \(ISO8601DateFormatter().string(from: Date())) (nothing was moved)"
        try? ([header] + lines).joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func describe(_ m: PlannedMove) -> String {
        let app = NSRunningApplication(processIdentifier: pid_t(m.pid))?.localizedName ?? "pid \(m.pid)"
        return "window \(m.windowID) [\(app)]: \(m.from.displayUUID.prefix(8)):\(m.from.spaceKey.prefix(8)) -> \(m.to.displayUUID.prefix(8)):\(m.to.spaceKey.prefix(8))"
    }

    private func beginReconfiguration() {
        guard isRunning else { return }
        history.freeze(at: ProcessInfo.processInfo.systemUptime)
    }

    private func endReconfiguration() {
        guard isRunning else { return }
        // The system keeps reshuffling windows for a moment; wait for it to settle, coalescing repeat callbacks.
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.settled() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func settled() {
        let layout = WindowSnapshotter.currentLayout()
        let previousDisplays = history.snapshots.last?.displays ?? []
        let removed = previousDisplays.subtracting(layout.displays)
        let added = layout.displays.subtracting(previousDisplays)

        if !removed.isEmpty, let before = history.snapshotBeforeDisconnect(of: removed) {
            let now = WindowSnapshotter.capture(layout: layout, now: ProcessInfo.processInfo.systemUptime)
            let moves = WindowMovePlanner.planCollapse(
                snapshot: before, groups: groupsProvider(), connected: layout.displays,
                spacesByDisplay: layout.spacesByDisplay, current: WindowSnapshotter.windowsByID(now))
            movedRecords = WindowMovePlanner.records(for: moves, snapshot: before)
            logger.info("dry-run collapse: display(s) removed=\(removed.count), planned moves=\(moves.count) (nothing moved)")
            let groups = groupsProvider()
            var lines = ["COLLAPSE after disconnect of \(removed.map { String($0.prefix(8)) }.sorted())",
                         "snapshot used: \(Int(ProcessInfo.processInfo.systemUptime - before.time)) s old, \(before.windows.count) windows",
                         "removed display(s) held \(before.windows.filter { removed.contains($0.location.displayUUID) }.count) windows; groups: \(groups.count)",
                         "planned moves: \(moves.count)"]
            lines += moves.map { "  " + describe($0) }
            writeReport(lines)
        } else if !added.isEmpty {
            let now = WindowSnapshotter.capture(layout: layout, now: ProcessInfo.processInfo.systemUptime)
            let moves = WindowMovePlanner.planRestore(
                records: movedRecords, connected: layout.displays,
                spacesByDisplay: layout.spacesByDisplay, current: WindowSnapshotter.windowsByID(now))
            logger.info("dry-run restore: display(s) added=\(added.count), planned moves=\(moves.count) (nothing moved)")
            var lines = ["RESTORE after reconnect of \(added.map { String($0.prefix(8)) }.sorted())",
                         "records from the last collapse: \(movedRecords.count); planned moves: \(moves.count)",
                         "(in a dry run nothing was collapsed, so windows are not where the records expect; 0 moves is expected)"]
            lines += moves.map { "  " + describe($0) }
            if let existing = try? String(contentsOf: Self.reportURL, encoding: .utf8) { lines = [existing, "---"] + lines }
            writeReport(lines)
            movedRecords = []
        }

        history.unfreeze()
        captureNow()
    }
}
