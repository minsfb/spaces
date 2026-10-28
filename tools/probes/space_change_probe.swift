// Probe for issue #4: how does activeSpaceDidChangeNotification relate to which display changed?
// Read-only. Polls current Space per display every 10 ms and logs, per notification:
// time, which displays changed (by diffing snapshots), and how long after the actual change
// (seen by polling) the notification arrived. Also logs changes seen by polling.
// Build: swiftc -O space_change_probe.swift -o /tmp/space_change_probe
// Output: /tmp/space_change_probe.log   Stop: kill it.
import AppKit
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ c: Int32) -> CFArray

setvbuf(stdout, nil, _IONBF, 0)
let conn = CGSMainConnectionID()
let t0 = Date()
func now() -> Double { Date().timeIntervalSince(t0) }
func current() -> [String: UInt64] {
    var r: [String: UInt64] = [:]
    for d in CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] ?? [] {
        if let u = d["Display Identifier"] as? String, let c = (d["Current Space"] as? [String: Any])?["id64"] as? UInt64 { r[u] = c }
    }
    return r
}
func short(_ u: String) -> String { String(u.prefix(4)) }
func diff(_ a: [String: UInt64], _ b: [String: UInt64]) -> [String] {
    b.keys.sorted().compactMap { u in
        guard let x = a[u], let y = b[u], x != y else { return nil }
        return "\(short(u)):\(x)->\(y)"
    }
}
var lines: [String] = []
func log(_ s: String) { let l = String(format: "%8.3f  %@", now(), s); lines.append(l); print(l) }

var lastSeen = current()                // by polling
var lastNotified = lastSeen             // at last notification
var pendingPollChanges: [(Double, [String])] = []   // changes seen by poll not yet matched to a notification

Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
    let c = current(); let d = diff(lastSeen, c)
    if !d.isEmpty { pendingPollChanges.append((now(), d)); log("poll saw change: \(d.joined(separator: ", "))"); lastSeen = c }
}
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
    let c = current(); let d = diff(lastNotified, c); lastNotified = c
    let lag = pendingPollChanges.first.map { String(format: "%.0f ms after poll saw change", (now() - $0.0) * 1000) } ?? "no preceding poll change"
    pendingPollChanges.removeAll()
    log("NOTIFICATION  changed=[\(d.joined(separator: ", "))]  (\(lag))")
}
log("start: \(lastSeen.map { "\(short($0.key))=\($0.value)" }.sorted().joined(separator: " "))")
let app = NSApplication.shared; app.setActivationPolicy(.accessory)
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    try? lines.joined(separator: "\n").write(toFile: "/tmp/space_change_probe.log", atomically: true, encoding: .utf8)
}
app.run()
