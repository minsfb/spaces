// Probe for issue #6 follow-up: what can the Accessibility API do for windows in
// other Spaces / on other displays? Requires Accessibility permission for the host.
// Build: swiftc -O ax_probe.swift -o /tmp/ax_probe  (needs /tmp/probe_window_helper)
import AppKit
import ApplicationServices

@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindows(_ c: Int32, _ mask: Int32, _ wids: CFArray) -> CFArray
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ c: Int32) -> CFArray
@_silgen_name("CGSGetActiveSpace") func CGSGetActiveSpace(_ c: Int32) -> Int

setvbuf(stdout, nil, _IONBF, 0)
guard AXIsProcessTrusted() else { print("Accessibility not granted to this host"); exit(1) }
let conn = CGSMainConnectionID()
func spaces(_ wid: Int) -> [Int] { (CGSCopySpacesForWindows(conn, 7, [wid] as CFArray) as? [Int]) ?? [] }
func nap(_ t: Double = 0.5) { Thread.sleep(forTimeInterval: t) }

// Displays
var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
CGGetActiveDisplayList(8, &ids, &n)
let displays = Array(ids.prefix(Int(n)))
guard let builtin = displays.first(where: { CGDisplayIsBuiltin($0) != 0 }),
      let external = displays.first(where: { CGDisplayIsBuiltin($0) == 0 }) else {
    print("need a built-in and an external display"); exit(1)
}
let bb = CGDisplayBounds(builtin), eb = CGDisplayBounds(external)
print("builtin bounds=\(bb) external bounds=\(eb)")

// currents per display
func currentSpaces() -> [String: Int] {
    var r: [String: Int] = [:]
    for d in CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] ?? [] {
        r[d["Display Identifier"] as? String ?? "?"] = (d["Current Space"] as? [String: Any])?["id64"] as? Int
    }
    return r
}
func uuid(_ id: CGDirectDisplayID) -> String {
    CFUUIDCreateString(nil, CGDisplayCreateUUIDFromDisplayID(id)!.takeRetainedValue()) as String
}
let cur = currentSpaces()
let builtinCur = cur[uuid(builtin)] ?? -1, externalCur = cur[uuid(external)] ?? -1
print("current Space: builtin=\(builtinCur) external=\(externalCur)")

func spawn(_ args: [String] = []) -> (Process, Int) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/tmp/probe_window_helper"); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; try! p.run()
    let s = String(data: pipe.fileHandleForReading.availableData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return (p, Int(s) ?? -1)
}
func axWindows(_ pid: pid_t) -> [AXUIElement] {
    var v: CFTypeRef?
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 2)
    let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v)
    if err != .success { print("    (AX windows error \(err.rawValue))") }
    return (v as? [AXUIElement]) ?? []
}
func axPos(_ w: AXUIElement) -> CGPoint? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &v) == .success else { return nil }
    var pt = CGPoint.zero; AXValueGetValue(v as! AXValue, .cgPoint, &pt); return pt
}
func axSetPos(_ w: AXUIElement, _ p: CGPoint) -> AXError {
    var pt = p; return AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &pt)!)
}

// --- A/B/C: helper window on the current Space; move across displays by AX position
print("spawning helper1")
let (h1, wid1) = spawn(); defer { h1.terminate() }
print("spawned wid=\(wid1)")
nap()
print("\n[A0] after pause")
let sp1 = spaces(wid1); print("[A1] spaces=\(sp1)")
let aw1 = axWindows(h1.processIdentifier); print("[A2] axWindows=\(aw1.count)")
if let w = axWindows(h1.processIdentifier).first {
    print("    initial AX position=\(String(describing: axPos(w)))")
    let toExternal = CGPoint(x: eb.maxX - 320, y: eb.maxY - 200)   // bottom-right corner of external
    let e1 = axSetPos(w, toExternal); nap(0.8)
    print("[B] AX move onto external: err=\(e1.rawValue) pos=\(String(describing: axPos(w))) spaces=\(spaces(wid1)) (external current=\(externalCur))")
    let toBuiltin = CGPoint(x: bb.minX + 100, y: bb.minY + 100)
    let e2 = axSetPos(w, toBuiltin); nap(0.8)
    print("[C] AX move back onto builtin: err=\(e2.rawValue) pos=\(String(describing: axPos(w))) spaces=\(spaces(wid1)) (builtin current=\(builtinCur))")
}

// --- D: helper moves its OWN window to a non-current builtin Space; can AX see it?
let allBuiltinSpaces: [Int] = {
    for d in CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] ?? [] where (d["Display Identifier"] as? String) == uuid(builtin) {
        return (d["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? Int) == 0 }.compactMap { $0["id64"] as? Int }
    }
    return []
}()
if let target = allBuiltinSpaces.first(where: { $0 != builtinCur }) {
    let (h2, wid2) = spawn(["--move-self-to", String(target)]); defer { h2.terminate() }
    nap()
    let wins = axWindows(h2.processIdentifier)
    print("\n[D] helper2 window \(wid2) placed in non-current Space \(target): spaces=\(spaces(wid2)) axWindows=\(wins.count)")
    if let w = wins.first {
        print("    AX position=\(String(describing: axPos(w)))  trying AX move onto external...")
        let e = axSetPos(w, CGPoint(x: eb.maxX - 320, y: eb.maxY - 200)); nap(0.8)
        print("    err=\(e.rawValue) spaces now=\(spaces(wid2)) (external current=\(externalCur))")
    }
} else { print("no non-current builtin Space to test [D]") }
print("\ndone")
