// Control for window_move_probe: a process moving ITS OWN window with the same CGS calls.
// If this works while moving another process's window does not, the probe is sound.
// Build: swiftc -O self_move_control.swift -o /tmp/self_move_control
import AppKit
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace") func CGSGetActiveSpace(_ c: Int32) -> Int
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindows(_ c: Int32, _ mask: Int32, _ wids: CFArray) -> CFArray
@_silgen_name("CGSMoveWindowsToManagedSpace") func CGSMoveWindowsToManagedSpace(_ c: Int32, _ w: CFArray, _ s: UInt64)
let target = Int(CommandLine.arguments.dropFirst().first ?? "3") ?? 3
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 200, height: 80),
                 styleMask: [.titled], backing: .buffered, defer: false)
w.orderFrontRegardless()
let c = CGSMainConnectionID(), wid = w.windowNumber
func sp() -> [Int] { (CGSCopySpacesForWindows(c, 7, [wid] as CFArray) as? [Int]) ?? [] }
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
let active = CGSGetActiveSpace(c)
print("own window \(wid): initial=\(sp())")
CGSMoveWindowsToManagedSpace(c, [wid] as CFArray, UInt64(target))
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
print("after move to \(target): \(sp())")
CGSMoveWindowsToManagedSpace(c, [wid] as CFArray, UInt64(active))
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
print("after move back to \(active): \(sp())")
