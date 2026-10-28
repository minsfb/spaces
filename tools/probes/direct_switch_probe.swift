// Probe for issue #5: can CGSManagedDisplaySetCurrentSpace switch a display's Space directly?
// SWITCHES THE USER'S SPACES (briefly) and restores them. Usage:
//   direct_switch_probe <builtin|external> [targetSpaceID]
// Build: swiftc -O direct_switch_probe.swift -o /tmp/direct_switch_probe
import AppKit

@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ c: Int32) -> CFArray
@_silgen_name("CGSManagedDisplaySetCurrentSpace") func CGSManagedDisplaySetCurrentSpace(_ c: Int32, _ display: CFString, _ space: UInt64)

setvbuf(stdout, nil, _IONBF, 0)
let conn = CGSMainConnectionID()
let t0 = Date()
func now() -> Double { Date().timeIntervalSince(t0) * 1000 }

struct Disp { let uuid: String; let current: UInt64; let spaces: [UInt64] }
func displays() -> [Disp] {
    (CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] ?? []).compactMap { d in
        guard let u = d["Display Identifier"] as? String,
              let c = (d["Current Space"] as? [String: Any])?["id64"] as? UInt64 else { return nil }
        let sp = (d["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? Int) == 0 }.compactMap { $0["id64"] as? UInt64 }
        return Disp(uuid: u, current: c, spaces: sp)
    }
}
func uuidOf(builtin: Bool) -> String? {
    var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
    CGGetActiveDisplayList(8, &ids, &n)
    for id in ids.prefix(Int(n)) where (CGDisplayIsBuiltin(id) != 0) == builtin {
        return CFUUIDCreateString(nil, CGDisplayCreateUUIDFromDisplayID(id)!.takeRetainedValue()) as String
    }
    return nil
}
// Window ids currently on screen (i.e., in a visible Space), layer 0, reasonably large
func onScreen() -> Set<Int> {
    let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return Set(l.compactMap { i -> Int? in
        guard (i[kCGWindowLayer as String] as? Int) == 0, let id = i[kCGWindowNumber as String] as? Int,
              let b = i[kCGWindowBounds as String] as? [String: CGFloat], (b["Width"] ?? 0) >= 100, (b["Height"] ?? 0) >= 60 else { return nil }
        return id
    })
}

let args = CommandLine.arguments
guard args.count >= 2, let uuid = uuidOf(builtin: args[1] == "builtin"),
      let me = displays().first(where: { $0.uuid == uuid }) else { print("usage: direct_switch_probe <builtin|external> [spaceID]"); exit(2) }
let target: UInt64 = (args.count >= 3 ? UInt64(args[2]) : nil) ?? me.spaces.first(where: { $0 != me.current })!
print("display \(uuid.prefix(4)) current=\(me.current) target=\(target)")

var notifications = 0
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
    notifications += 1; print(String(format: "  [%.0f ms] activeSpaceDidChange notification #%d", now(), notifications))
}
func pump(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }
func cur() -> UInt64? { displays().first(where: { $0.uuid == uuid })?.current }

let before = onScreen()
let tSet = now()
CGSManagedDisplaySetCurrentSpace(conn, uuid as CFString, target)
var seenAt: Double? = nil
for _ in 0..<100 { pump(0.01); if cur() == target { seenAt = now(); break } }
print(String(format: "current after set: %@ (bookkeeping changed after %@)", String(describing: cur()), seenAt.map { String(format: "%.0f ms", $0 - tSet) } ?? "never"))
pump(0.6)
let after = onScreen()
print("on-screen windows before=\(before.count) after=\(after.count); appeared=\(after.subtracting(before).count) disappeared=\(before.subtracting(after).count)")
print("notifications so far: \(notifications)")

// restore
CGSManagedDisplaySetCurrentSpace(conn, uuid as CFString, me.current)
pump(0.8)
let restored = onScreen()
print("restored current=\(String(describing: cur())) (expected \(me.current)); on-screen windows now=\(restored.count), same set as before: \(restored == before)")
print("total notifications: \(notifications)")
