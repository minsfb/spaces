// Read-only: measures the cost of snapshotting every window's Space membership.
// Build: swiftc -O snapshot_cost.swift -o /tmp/snapshot_cost
import Foundation
import CoreGraphics
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindows(_ c: Int32, _ mask: Int32, _ wids: CFArray) -> CFArray
let conn = CGSMainConnectionID()
func ms(_ f: () -> Void) -> Double { let t = DispatchTime.now(); f(); return Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e6 }
var all: [[String: Any]] = []
var tAll = [Double](), tSpaces = [Double]()
for _ in 0..<20 {
    tAll.append(ms { all = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? [] })
    let ids = all.compactMap { $0[kCGWindowNumber as String] as? Int }
    tSpaces.append(ms { _ = CGSCopySpacesForWindows(conn, 7, ids as CFArray) })
}
let normal = all.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
let ids = all.compactMap { $0[kCGWindowNumber as String] as? Int }
let sp = (CGSCopySpacesForWindows(conn, 7, ids as CFArray) as? [Int]) ?? []
// spaces call returns a flat union list; per-window needs per-call: measure that too
var tPer = 0.0
tPer = ms { for id in normal.compactMap({ $0[kCGWindowNumber as String] as? Int }) { _ = CGSCopySpacesForWindows(conn, 7, [id] as CFArray) } }
func avg(_ a: [Double]) -> String { String(format: "%.2f", a.reduce(0, +) / Double(a.count)) }
print("windows total=\(all.count) layer0=\(normal.count)")
print("CGWindowListCopyWindowInfo(optionAll): avg \(avg(tAll)) ms")
print("CGSCopySpacesForWindows (one batch call): avg \(avg(tSpaces)) ms")
print(String(format: "per-window spaces lookups for %d layer-0 windows: %.2f ms total", normal.count, tPer))
print("distinct spaces in batch result: \(Set(sp).sorted())")
