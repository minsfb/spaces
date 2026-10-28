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
            for m in moves {
                logger.info("  would move window \(m.windowID): \(m.from.spaceKey, privacy: .public) -> \(m.to.spaceKey, privacy: .public)")
            }
        } else if !added.isEmpty {
            let now = WindowSnapshotter.capture(layout: layout, now: ProcessInfo.processInfo.systemUptime)
            let moves = WindowMovePlanner.planRestore(
                records: movedRecords, connected: layout.displays,
                spacesByDisplay: layout.spacesByDisplay, current: WindowSnapshotter.windowsByID(now))
            logger.info("dry-run restore: display(s) added=\(added.count), planned moves=\(moves.count) (nothing moved)")
            movedRecords = []
        }

        history.unfreeze()
        captureNow()
    }
}
