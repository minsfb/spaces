// Probe for issue #6: can another process's window be moved between Spaces
// via private CGS calls, without SIP changes?
// Creates a throwaway TextEdit document, tries each mechanism, verifies membership
// with CGSCopySpacesForWindows, then closes the document.
// Build: swiftc -O window_move_probe.swift -o /tmp/window_move_probe
import Foundation
import CoreGraphics

@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ c: Int32) -> CFArray
@_silgen_name("CGSGetActiveSpace") func CGSGetActiveSpace(_ c: Int32) -> Int
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindows(_ c: Int32, _ mask: Int32, _ wids: CFArray) -> CFArray
@_silgen_name("CGSAddWindowsToSpaces") func CGSAddWindowsToSpaces(_ c: Int32, _ w: CFArray, _ s: CFArray)
@_silgen_name("CGSRemoveWindowsFromSpaces") func CGSRemoveWindowsFromSpaces(_ c: Int32, _ w: CFArray, _ s: CFArray)
@_silgen_name("CGSMoveWindowsToManagedSpace") func CGSMoveWindowsToManagedSpace(_ c: Int32, _ w: CFArray, _ s: UInt64)

let conn = CGSMainConnectionID()

func osa(_ script: String) -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    let o = Pipe(); p.standardOutput = o; p.standardError = o
    try? p.run(); p.waitUntilExit()
    return String(data: o.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}
func spaces(of wid: Int) -> [Int] {
    (CGSCopySpacesForWindows(conn, 7, [wid] as CFArray) as? [Int]) ?? []
}
func report(_ label: String, _ wid: Int) { print("  \(label): spaces=\(spaces(of: wid))"); fflush(stdout) }

// Layout
var userSpaces: [(display: String, id: Int, current: Bool)] = []
for d in CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] ?? [] {
    let disp = d["Display Identifier"] as? String ?? "?"
    let cur = (d["Current Space"] as? [String: Any])?["id64"] as? Int ?? -1
    for s in d["Spaces"] as? [[String: Any]] ?? [] where (s["type"] as? Int) == 0 {
        let id = s["id64"] as? Int ?? -1
        userSpaces.append((disp, id, id == cur))
    }
}
let active = CGSGetActiveSpace(conn)
print("active space=\(active)")

// Helper process owning the throwaway window
let helper = Process()
helper.executableURL = URL(fileURLWithPath: "/tmp/probe_window_helper")
let hp = Pipe(); helper.standardOutput = hp
try helper.run()
defer { helper.terminate() }
let line = String(data: hp.fileHandleForReading.availableData, encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
guard let wid = Int(line) else { print("no window id from helper: \(line)"); exit(1) }
print("test window id=\(wid) owned by helper pid \(helper.processIdentifier)")
Thread.sleep(forTimeInterval: 0.5)
report("initial", wid)

// Targets: another Space on the SAME display as the active Space, not current
let activeDisplay = userSpaces.first { $0.id == active }?.display
var sameDisplayTarget = userSpaces.first { $0.display == activeDisplay && !$0.current }
if let i = CommandLine.arguments.firstIndex(of: "--target"), i + 1 < CommandLine.arguments.count,
   let t = Int(CommandLine.arguments[i + 1]) {
    sameDisplayTarget = userSpaces.first { $0.id == t && $0.display == activeDisplay } ?? sameDisplayTarget
}
let otherDisplayTarget = userSpaces.first { $0.display != activeDisplay }

func tryMove(_ name: String, target: Int, _ f: () -> Void) {
    print("== \(name) -> space \(target)")
    f(); Thread.sleep(forTimeInterval: 0.4)
    report("after", wid)
}

if let t = sameDisplayTarget {
    tryMove("CGSMoveWindowsToManagedSpace (same display, inactive Space)", target: t.id) {
        CGSMoveWindowsToManagedSpace(conn, [wid] as CFArray, UInt64(t.id))
    }
    // put it back, then try add/remove
    CGSMoveWindowsToManagedSpace(conn, [wid] as CFArray, UInt64(active)); Thread.sleep(forTimeInterval: 0.4)
    report("reset", wid)
    tryMove("CGSAddWindowsToSpaces + CGSRemoveWindowsFromSpaces (same display)", target: t.id) {
        CGSAddWindowsToSpaces(conn, [wid] as CFArray, [t.id] as CFArray)
        CGSRemoveWindowsFromSpaces(conn, [wid] as CFArray, [active] as CFArray)
    }
    CGSMoveWindowsToManagedSpace(conn, [wid] as CFArray, UInt64(active)); Thread.sleep(forTimeInterval: 0.4)
    report("reset", wid)
} else { print("no second Space on active display; skipping same-display tests") }

if CommandLine.arguments.contains("--cross-display"), let t = otherDisplayTarget {
    tryMove("CGSMoveWindowsToManagedSpace (other display)", target: t.id) {
        CGSMoveWindowsToManagedSpace(conn, [wid] as CFArray, UInt64(t.id))
    }
    CGSMoveWindowsToManagedSpace(conn, [wid] as CFArray, UInt64(active)); Thread.sleep(forTimeInterval: 0.4)
    report("reset", wid)
    tryMove("Add+Remove (other display)", target: t.id) {
        CGSAddWindowsToSpaces(conn, [wid] as CFArray, [t.id] as CFArray)
        CGSRemoveWindowsFromSpaces(conn, [wid] as CFArray, [active] as CFArray)
    }
} else if otherDisplayTarget != nil { print("(skipping cross-display; pass --cross-display)") }
print("done")
