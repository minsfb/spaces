// Throwaway helper: owns one window so probes can move "another process's window".
// Prints its CGWindowID on stdout, then runs until killed. No Dock icon, no focus steal.
// Build: swiftc -O probe_window_helper.swift -o /tmp/probe_window_helper
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 280, height: 120),
                 styleMask: [.titled], backing: .buffered, defer: false)
w.title = "spaces-probe-window"
w.level = .normal
w.orderFrontRegardless()
print(w.windowNumber); fflush(stdout)
app.run()
