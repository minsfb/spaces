import AppKit

/// Decides whether it is safe to post synthetic input (locked or sleeping screens could send keystrokes to the
/// password field). Not wired into anything yet: window-move executors must call `begin()` before a run and
/// `checkpoint()` before every batch of synthetic input, and stop when it returns false.
final class SessionGuard: @unchecked Sendable {
    // Mutated on the main thread only (notifications are delivered there); checkpoint() may be called from any thread
    // but only reads through the lock.
    private let lock = NSLock()
    private var latch = InterruptionLatch()
    private var observers: [NSObjectProtocol] = []

    init() {
        let interrupt: (Notification) -> Void = { [weak self] _ in self?.withLock { $0.interrupt() } }
        let dnc = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            observers.append(dnc.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main, using: interrupt))
        }
        let ws = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                  NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(ws.addObserver(forName: n, object: nil, queue: .main, using: interrupt))
        }
    }

    deinit {
        for o in observers { DistributedNotificationCenter.default().removeObserver(o); NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    /// Current state read from the system.
    static func currentState() -> SessionState {
        let d = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        return SessionState(
            screenLocked: (d["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false,
            onConsole: (d["kCGSSessionOnConsoleKey"] as? NSNumber)?.boolValue ?? false,
            loginDone: (d["kCGSessionLoginDoneKey"] as? NSNumber)?.boolValue ?? false,
            displayAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0,
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// Start of an automated run. False means do not start; see `currentState().blockers`.
    func begin() -> Bool { withLock { $0.begin(state: Self.currentState()) } }

    /// Before each batch of synthetic input. False means stop immediately and leave the rest undone.
    func checkpoint() -> Bool { withLock { $0.shouldContinue(state: Self.currentState()) } }

    private func withLock<T>(_ body: (inout InterruptionLatch) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(&latch)
    }
}
