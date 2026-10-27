// Throwaway helper: owns one window so probes can move "another process's window".
// Prints its CGWindowID on stdout, then runs until killed. No Dock icon, no focus steal.
// Build: swiftc -O probe_window_helper.swift -o /tmp/probe_window_helper
import AppKit
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> Int32
@_silgen_name("CGSMoveWindowsToManagedSpace") func CGSMoveWindowsToManagedSpace(_ c: Int32, _ w: CFArray, _ s: UInt64)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 280, height: 120),
                 styleMask: [.titled], backing: .buffered, defer: false)
func arg(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}
w.title = arg("--title") ?? "spaces-probe-window"
// Optional: --origin x,y places the window (Cocoa coordinates: origin bottom-left of the primary display).
if let o = arg("--origin")?.split(separator: ",").compactMap({ Double($0) }), o.count == 2 {
    w.setFrameOrigin(NSPoint(x: o[0], y: o[1]))
}
w.level = .normal
w.orderFrontRegardless()
// Optional: --move-self-to <spaceID> moves this helper's OWN window (allowed) to that Space.
if let i = CommandLine.arguments.firstIndex(of: "--move-self-to"), i + 1 < CommandLine.arguments.count,
   let sid = UInt64(CommandLine.arguments[i + 1]) {
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    CGSMoveWindowsToManagedSpace(CGSMainConnectionID(), [w.windowNumber] as CFArray, sid)
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
}
print(w.windowNumber); fflush(stdout)
app.run()
