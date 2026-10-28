import Foundation

/// Facts about the login session relevant to whether it is safe to post synthetic keystrokes and mouse events.
/// Observed on macOS 26: `CGSSessionScreenIsLocked` appears in the session dictionary while locked (it can appear
/// before the lock notification on sleep); waking the display does not unlock; `CGDisplayIsAsleep` and the
/// frontmost app lag the lock, so none of them alone is sufficient.
struct SessionState: Equatable {
    var screenLocked: Bool
    var onConsole: Bool
    var loginDone: Bool
    var displayAsleep: Bool
    var frontmostBundleID: String?

    /// Reasons it is NOT safe to automate input right now (empty means safe).
    var blockers: [String] {
        var b: [String] = []
        if screenLocked { b.append("screen locked") }
        if !onConsole { b.append("session not on console") }
        if !loginDone { b.append("login not finished") }
        if displayAsleep { b.append("display asleep") }
        if frontmostBundleID == "com.apple.loginwindow" { b.append("login window frontmost") }
        return b
    }

    var isSafe: Bool { blockers.isEmpty }
}

/// Latch deciding whether an automated run may start or continue. Lock/sleep/session-resign events trip it
/// immediately (they arrive faster than the polled state changes); a run can only start from a clean, safe state.
struct InterruptionLatch: Equatable {
    private(set) var interrupted = false

    mutating func interrupt() { interrupted = true }

    /// Begin a new run: allowed only if the session is safe now. Clears any earlier interruption.
    mutating func begin(state: SessionState) -> Bool {
        guard state.isSafe else { return false }
        interrupted = false
        return true
    }

    /// Call before every batch of synthetic input. False means stop now and leave the rest undone.
    func shouldContinue(state: SessionState) -> Bool { !interrupted && state.isSafe }
}
