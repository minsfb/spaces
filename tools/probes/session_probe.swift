// Probe: which signals does macOS give us for "screen locked / asleep / session inactive"?
// Read-only. Logs the session dictionary state at start, every change seen by 500 ms polling
// (locked flag, on-console, display asleep, frontmost app), and these notifications:
//   com.apple.screenIsLocked / screenIsUnlocked, screensaver start/stop (distributed),
//   NSWorkspace screens sleep/wake, system sleep/wake, session resign/become active.
// Build: swiftc -O session_probe.swift -o /tmp/session_probe
// Output: /tmp/session_probe.log  (also stdout). Stop: kill it.
import AppKit

setvbuf(stdout, nil, _IONBF, 0)
let t0 = Date()
var lines: [String] = []
func log(_ s: String) {
    let l = String(format: "%8.2f  %@", Date().timeIntervalSince(t0), s)
    lines.append(l); print(l)
    try? lines.joined(separator: "\n").write(toFile: "/tmp/session_probe.log", atomically: true, encoding: .utf8)
}

func state() -> String {
    let d = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    let locked = (d["CGSSessionScreenIsLocked"] as? NSNumber)?.intValue
    let onConsole = (d["kCGSSessionOnConsoleKey"] as? NSNumber)?.intValue
    let loginDone = (d["kCGSessionLoginDoneKey"] as? NSNumber)?.intValue
    let asleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
    let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    return "lockedKey=\(locked.map(String.init) ?? "absent") onConsole=\(onConsole.map(String.init) ?? "absent") loginDone=\(loginDone.map(String.init) ?? "absent") displayAsleep=\(asleep) front=\(front) idle=\(Int(idle))s"
}
func stateKey() -> String {  // everything except idle, so polling only logs real changes
    state().replacingOccurrences(of: #" idle=\d+s"#, with: "", options: .regularExpression)
}

log("start: \(state())")
var last = stateKey()
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    let k = stateKey()
    if k != last { log("POLL change: \(state())"); last = k }
}
let dnc = DistributedNotificationCenter.default()
for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked", "com.apple.screensaver.didstart", "com.apple.screensaver.didstop"] {
    dnc.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { _ in log("NOTIFY \(name)") }
}
let ws = NSWorkspace.shared.notificationCenter
for n in [NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.willSleepNotification,
          NSWorkspace.didWakeNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
    ws.addObserver(forName: n, object: nil, queue: .main) { _ in log("NOTIFY \(n.rawValue)") }
}
let app = NSApplication.shared; app.setActivationPolicy(.accessory); app.run()
