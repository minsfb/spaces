import AppKit
import ApplicationServices
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.spaceswitcher.SpaceSwitcher", category: "OverlayManager")

@Observable
@MainActor
final class OverlayState {
    var focusedIndex: Int = 0
}

@MainActor
final class OverlayManager {
    private var panels: [OverlayPanel] = []
    private var appState: AppState
    private var overlayState = OverlayState()
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var rightClickMonitor: Any?
    private var previousAppPID: pid_t?

    var isVisible: Bool { panels.contains { $0.isVisible } }

    init(appState: AppState) {
        self.appState = appState
    }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        dismiss()

        appState.refreshMonitors()
        appState.detectActiveGroup()

        guard !appState.groups.isEmpty else { return }

        // Start focused on the active group
        if let activeID = appState.activeGroupID,
           let idx = appState.groups.firstIndex(where: { $0.id == activeID }) {
            overlayState.focusedIndex = idx
        } else {
            overlayState.focusedIndex = 0
        }

        // Capture the frontmost app before our overlay takes focus
        let myPID = ProcessInfo.processInfo.processIdentifier
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.processIdentifier != myPID {
            previousAppPID = frontApp.processIdentifier
        }

        buildPanels()

        // Keyboard handling via local monitor (reliable for non-activating panels)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }

        // Right-click on overlay icons to move frontmost window
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            let groups = self.appState.groups
            guard !groups.isEmpty else { return event }
            self.moveFrontmostWindow(toGroup: groups[self.overlayState.focusedIndex])
            return nil  // consume the event
        }

        // Click-outside dismissal
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let groups = appState.groups
        guard !groups.isEmpty else { return false }

        switch Int(event.keyCode) {
        case 53: // Escape
            dismiss()
            return true
        case 36: // Return
            dismissThenSwitch(groups[overlayState.focusedIndex])
            return true
        case 123: // Left arrow
            overlayState.focusedIndex = (overlayState.focusedIndex - 1 + groups.count) % groups.count
            return true
        case 124: // Right arrow
            overlayState.focusedIndex = (overlayState.focusedIndex + 1) % groups.count
            return true
        default:
            // Number keys 1-9
            if let chars = event.characters, let digit = Int(chars), digit >= 1, digit <= groups.count {
                dismissThenSwitch(groups[digit - 1])
                return true
            }
            return false
        }
    }

    private func buildPanels() {
        for screen in NSScreen.screens {
            let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 500))

            let overlayView = OverlayView(
                onGroupSelected: { [weak self] group in
                    self?.dismissThenSwitch(group)
                }
            )
            .environment(appState)
            .environment(overlayState)

            let hostingView = NSHostingView(rootView: overlayView)
            panel.contentView = hostingView

            hostingView.layoutSubtreeIfNeeded()
            let fittingSize = hostingView.fittingSize
            panel.setContentSize(fittingSize)

            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - fittingSize.width / 2
            let y = screenFrame.midY - fittingSize.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))

            panel.makeKeyAndOrderFront(nil)
            panels.append(panel)
        }
    }

    /// Find a safe point on the title bar to grab. Uses AX to find empty space,
    /// falls back to right side, then center.
    private func findTitleBarGrabPoint(axWindow: AXUIElement, position: CGPoint, size: CGSize) -> CGPoint {
        // Try 1: Find AX title bar element and locate empty space
        var childrenValue: AnyObject?
        if AXUIElementCopyAttributeValue(axWindow, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children {
                var subroleValue: AnyObject?
                AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subroleValue)

                guard let subrole = subroleValue as? String, subrole == "AXTitleBar" else { continue }

                // Found title bar — get its frame
                var tbPosValue: AnyObject?
                var tbSizeValue: AnyObject?
                AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &tbPosValue)
                AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &tbSizeValue)

                var tbPos = CGPoint.zero
                var tbSize = CGSize.zero
                if let p = tbPosValue { AXValueGetValue(p as! AXValue, .cgPoint, &tbPos) }
                if let s = tbSizeValue { AXValueGetValue(s as! AXValue, .cgSize, &tbSize) }
                let tbY = tbPos.y + tbSize.height / 2

                // Get all title bar children bounding rects
                var tbChildrenValue: AnyObject?
                if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &tbChildrenValue) == .success,
                   let tbChildren = tbChildrenValue as? [AXUIElement], !tbChildren.isEmpty {

                    // Collect all child rects
                    var rects: [(x: CGFloat, width: CGFloat)] = []
                    for tbChild in tbChildren {
                        var cPosValue: AnyObject?
                        var cSizeValue: AnyObject?
                        AXUIElementCopyAttributeValue(tbChild, kAXPositionAttribute as CFString, &cPosValue)
                        AXUIElementCopyAttributeValue(tbChild, kAXSizeAttribute as CFString, &cSizeValue)
                        var cPos = CGPoint.zero
                        var cSize = CGSize.zero
                        if let p = cPosValue { AXValueGetValue(p as! AXValue, .cgPoint, &cPos) }
                        if let s = cSizeValue { AXValueGetValue(s as! AXValue, .cgSize, &cSize) }
                        if cSize.width > 0 {
                            rects.append((x: cPos.x, width: cSize.width))
                        }
                    }
                    rects.sort { $0.x < $1.x }

                    // Find the largest gap between children (or between last child and right edge)
                    let tbLeft = tbPos.x
                    let tbRight = tbPos.x + tbSize.width
                    var bestGapCenter = tbRight - 20.0
                    var bestGapWidth: CGFloat = 0

                    // Gap after rightmost child to right edge of title bar
                    if let last = rects.last {
                        let gapStart = last.x + last.width
                        let gapWidth = tbRight - gapStart
                        if gapWidth > bestGapWidth {
                            bestGapWidth = gapWidth
                            bestGapCenter = gapStart + gapWidth / 2
                        }
                    }

                    // Gaps between consecutive children
                    for i in 1..<rects.count {
                        let gapStart = rects[i - 1].x + rects[i - 1].width
                        let gapWidth = rects[i].x - gapStart
                        if gapWidth > bestGapWidth {
                            bestGapWidth = gapWidth
                            bestGapCenter = gapStart + gapWidth / 2
                        }
                    }

                    // Gap from title bar left edge to first child
                    if let first = rects.first {
                        let gapWidth = first.x - tbLeft
                        if gapWidth > bestGapWidth {
                            bestGapWidth = gapWidth
                            bestGapCenter = tbLeft + gapWidth / 2
                        }
                    }

                    if bestGapWidth >= 20 {
                        return CGPoint(x: bestGapCenter, y: tbY)
                    }
                }

                // No good gap found, try right side of title bar
                return CGPoint(x: tbPos.x + tbSize.width - 20, y: tbY)
            }
        }

        // Fallback: right side of window (past toolbar area)
        return CGPoint(x: position.x + size.width - 50, y: position.y + 15)
    }

    /// Move the frontmost window of the previously active app to the target group's space.
    /// Grabs window title bar via mouse hold, switches space with Ctrl+Number, then switches back.
    private func moveFrontmostWindow(toGroup group: DesktopGroup) {
        guard let pid = previousAppPID else { return }

        let appElement = AXUIElementCreateApplication(pid)
        var focusedValue: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedValue)
        guard focusedResult == .success, let windowElement = focusedValue else { return }
        let axWindow = windowElement as! AXUIElement

        var posValue: AnyObject?
        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posValue)
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeValue)

        var position = CGPoint.zero
        var size = CGSize.zero
        if let posValue { AXValueGetValue(posValue as! AXValue, .cgPoint, &position) }
        if let sizeValue { AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) }

        // Determine which monitor the window is on
        let windowCenter = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        let monitors = appState.monitors
        let monitor = monitors.first { $0.frame.contains(windowCenter) } ?? monitors.first
        guard let monitor else { return }
        guard let spaceIndex = group.spaceIndex(on: monitor) else { return }
        let targetIdx = spaceIndex - 1  // convert 1-based index to array index
        guard targetIdx >= 0, targetIdx < monitor.spaces.count else { return }
        let targetDesktop = monitor.spaces[targetIdx].desktopNumber

        let currentSpaces = SpaceSwitcherService.getCurrentSpacePerDisplay()
        guard let currentSpaceID = currentSpaces[monitor.displayUUID],
              let currentIdx = monitor.spaces.firstIndex(where: { $0.spaceID == currentSpaceID }) else { return }

        let moves = targetIdx - currentIdx
        guard moves != 0 else { return }

        // Find a safe grab point on the title bar (avoids tabs, toolbar buttons)
        let grabPoint = findTitleBarGrabPoint(axWindow: axWindow, position: position, size: size)

        dismiss()

        let app = NSRunningApplication(processIdentifier: pid)
        app?.activate()
        let overlayMgr = self

        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.3) {
            let source = CGEventSource(stateID: .combinedSessionState)

            // Warp cursor to the safe title bar grab point and hold mouse down
            CGWarpMouseCursorPosition(grabPoint)
            usleep(100_000)

            let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                     mouseCursorPosition: grabPoint, mouseButton: .left)
            mouseDown?.post(tap: .cghidEventTap)
            usleep(200_000)

            // Switch to target space via Ctrl+Number while holding title bar
            if let mapping = KeyCodes.keyMapping(for: targetDesktop) {
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: mapping.keyCode, keyDown: true)
                keyDown?.flags = mapping.flags
                keyDown?.post(tap: .cghidEventTap)
                usleep(50_000)
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: mapping.keyCode, keyDown: false)
                keyUp?.flags = mapping.flags
                keyUp?.post(tap: .cghidEventTap)
            }

            usleep(600_000) // wait for space animation

            // Release mouse — window is now on the target space
            let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                                   mouseCursorPosition: grabPoint, mouseButton: .left)
            mouseUp?.post(tap: .cghidEventTap)

            // Switch back to original space
            usleep(300_000)
            let originalDesktop = monitor.spaces[currentIdx].desktopNumber
            if let mapping = KeyCodes.keyMapping(for: originalDesktop) {
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: mapping.keyCode, keyDown: true)
                keyDown?.flags = mapping.flags
                keyDown?.post(tap: .cghidEventTap)
                usleep(50_000)
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: mapping.keyCode, keyDown: false)
                keyUp?.flags = mapping.flags
                keyUp?.post(tap: .cghidEventTap)
            }

            usleep(500_000)
            DispatchQueue.main.async {
                overlayMgr.show()
            }
        }
    }

    /// Dismiss the overlay, then switch spaces after a brief delay to avoid flashing.
    private func dismissThenSwitch(_ group: DesktopGroup) {
        dismiss()
        let state = appState
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            state.switchToGroup(group)
        }
    }

    func dismiss() {
        for panel in panels {
            panel.alphaValue = 0
            panel.orderOut(nil)
        }
        panels.removeAll()

        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = rightClickMonitor {
            NSEvent.removeMonitor(monitor)
            rightClickMonitor = nil
        }
    }
}
