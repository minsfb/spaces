// Read-only probe: dumps displays, Spaces and current Space per display.
// Build: swiftc -O spaces_dump.swift -o /tmp/spaces_dump
import Foundation
import CoreGraphics

@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ c: Int32) -> CFArray

let conn = CGSMainConnectionID()
let displays = CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] ?? []
for d in displays {
    let id = d["Display Identifier"] as? String ?? "?"
    let cur = (d["Current Space"] as? [String: Any])?["id64"] ?? "?"
    print("display \(id) current=\(cur)")
    for s in d["Spaces"] as? [[String: Any]] ?? [] {
        print("  space id64=\(s["id64"] ?? "?") type=\(s["type"] ?? "?") uuid=\(s["uuid"] ?? "?")")
    }
}
