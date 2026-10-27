// Passive logger for issues #1 and #3 (and #2's "IDs stable" assumption).
// Polls a window/Space snapshot every second and records display reconfiguration events,
// so one real unplug/replug shows: which hook fires first, where windows land, and whether
// window IDs and external-display Space IDs survive.
// Does NOT record window titles. Output: JSON lines at /tmp/unplug_log.jsonl (local only).
// Build: swiftc -O unplug_logger.swift -o /tmp/unplug_logger
// Run:   /tmp/unplug_logger [intervalSeconds]     Stop: kill it.
import AppKit
import Foundation

@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindows(_ c: Int32, _ mask: Int32, _ wids: CFArray) -> CFArray
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ c: Int32) -> CFArray

let conn = CGSMainConnectionID()
let interval = Double(CommandLine.arguments.dropFirst().first ?? "1") ?? 1
let outPath = "/tmp/unplug_log.jsonl"
FileManager.default.createFile(atPath: outPath, contents: nil)
let out = FileHandle(forWritingAtPath: outPath)!
let t0 = Date()
func now() -> Double { Date().timeIntervalSince(t0) }

func emit(_ obj: [String: Any]) {
    var o = obj; o["t"] = (now() * 1000).rounded() / 1000
    if let d = try? JSONSerialization.data(withJSONObject: o), var s = String(data: d, encoding: .utf8) {
        s += "\n"; out.write(s.data(using: .utf8)!)
    }
}

struct Win: Equatable { let id: Int; let pid: Int; let owner: String; let spaces: [Int]; let x: Int, y: Int, w: Int, h: Int }

func layout() -> [String: Any] {
    var r: [[String: Any]] = []
    for d in (CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] ?? []) {
        let cur = (d["Current Space"] as? [String: Any])?["id64"] as? Int ?? -1
        let sp = (d["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? Int) == 0 }.compactMap { $0["id64"] as? Int }
        r.append(["display": d["Display Identifier"] as? String ?? "?", "current": cur, "spaces": sp])
    }
    var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
    CGGetActiveDisplayList(8, &ids, &n)
    let active = ids.prefix(Int(n)).map { id -> [String: Any] in
        let u = CFUUIDCreateString(nil, CGDisplayCreateUUIDFromDisplayID(id)!.takeRetainedValue()) as String
        let b = CGDisplayBounds(id)
        return ["uuid": u, "builtin": CGDisplayIsBuiltin(id) != 0, "x": Int(b.minX), "y": Int(b.minY), "w": Int(b.width), "h": Int(b.height)]
    }
    return ["managed": r, "active": active]
}

func snapshot() -> [Win] {
    guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
    var res: [Win] = []
    for i in list {
        guard (i[kCGWindowLayer as String] as? Int) == 0,
              let id = i[kCGWindowNumber as String] as? Int,
              let pid = i[kCGWindowOwnerPID as String] as? Int,
              let b = i[kCGWindowBounds as String] as? [String: CGFloat],
              (i[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              (b["Width"] ?? 0) >= 100, (b["Height"] ?? 0) >= 60 else { continue }
        let sp = (CGSCopySpacesForWindows(conn, 7, [id] as CFArray) as? [Int]) ?? []
        if sp.isEmpty { continue }
        res.append(Win(id: id, pid: pid, owner: i[kCGWindowOwnerName as String] as? String ?? "?", spaces: sp,
                       x: Int(b["X"] ?? 0), y: Int(b["Y"] ?? 0), w: Int(b["Width"] ?? 0), h: Int(b["Height"] ?? 0)))
    }
    return res.sorted { $0.id < $1.id }
}
func enc(_ w: [Win]) -> [[String: Any]] {
    w.map { ["id": $0.id, "pid": $0.pid, "app": $0.owner, "spaces": $0.spaces, "x": $0.x, "y": $0.y, "w": $0.w, "h": $0.h] }
}

var ring: [(Double, [Win])] = []
var lastWritten: [Win] = []
var burstUntil = 0.0
func tick(_ reason: String, force: Bool = false) {
    let s = snapshot()
    ring.append((now(), s)); if ring.count > 10 { ring.removeFirst() }
    if force || s != lastWritten || now() < burstUntil {
        emit(["ev": "snap", "reason": reason, "layout": layout(), "windows": enc(s)])
        lastWritten = s
    }
}
func burst(_ label: String) {
    burstUntil = now() + 12
    for d in [0.0, 0.3, 1.0, 2.0, 4.0, 8.0] {
        DispatchQueue.main.asyncAfter(deadline: .now() + d) { tick("\(label)+\(d)s", force: true) }
    }
}

CGDisplayRegisterReconfigurationCallback({ id, flags, _ in
    // Runs on the main thread. 'begin' fires BEFORE the change; use the last ring entries as pre-state.
    let isBegin = flags.contains(.beginConfigurationFlag)
    emit(["ev": isBegin ? "displayBegin" : "displayEnd", "display": id, "flags": flags.rawValue,
          "add": flags.contains(.addFlag), "remove": flags.contains(.removeFlag),
          "ringAges": ring.map { (((now() - $0.0) * 1000).rounded() / 1000) }])
    if isBegin {
        // live snapshot taken at the very moment of the begin callback
        tick("atBegin", force: true)
    } else { burst("afterEnd") }
}, nil)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
    emit(["ev": "didChangeScreenParameters"]); burst("screenParams")
}
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
    emit(["ev": "activeSpaceDidChange"]); tick("spaceChange", force: true)
}
emit(["ev": "start", "interval": interval, "boot": ProcessInfo.processInfo.systemUptime])
tick("start", force: true)
Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in tick("poll") }
app.run()
