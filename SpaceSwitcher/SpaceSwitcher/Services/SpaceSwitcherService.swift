import AppKit
import CoreGraphics
import Foundation
import os.log

private let logger = Logger(subsystem: "com.spaceswitcher", category: "SpaceSwitcher")

enum SpaceSwitcherService {
    @MainActor
    static func switchToGroup(_ group: DesktopGroup, monitors: [MonitorInfo]) async {
        logger.info("=== switchToGroup called: \(group.name, privacy: .public) ===")

        let conn = CGSMainConnectionID()
        logger.info("CGSMainConnectionID: \(conn)")

        let currentSpaceByUUID = getCurrentSpacePerDisplay(connection: conn)
        let currentSpacesDesc = currentSpaceByUUID.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        logger.info("Current spaces by UUID: \(currentSpacesDesc, privacy: .public)")

        logger.info("Monitors count: \(monitors.count)")
        for monitor in monitors {
            let spacesDesc = monitor.spaces.map { "d\($0.desktopNumber)=\($0.spaceID)" }.joined(separator: ",")
            logger.info("  Monitor '\(monitor.id, privacy: .public)' displayUUID='\(monitor.displayUUID, privacy: .public)' spaces=\(spacesDesc, privacy: .public)")
        }

        logger.info("Group displaySpaces entries: \(group.displaySpaces.count)")

        let trusted = AXIsProcessTrusted()
        logger.info("AXIsProcessTrusted: \(trusted)")

        if !trusted {
            logger.warning("Accessibility NOT granted — CGEvent will be skipped, trying AppleScript fallback.")
            AccessibilityManager.checkAndPrompt()
        }

        var desktopsToSwitch: [Int] = []

        for monitor in monitors {
            guard group.hasSpace(on: monitor) else {
                logger.warning("  Monitor '\(monitor.id, privacy: .public)': no space in group, skipping")
                continue
            }
            guard let spaceInfo = group.space(on: monitor) else {
                logger.warning("  Monitor '\(monitor.id, privacy: .public)': group's space no longer exists, skipping")
                continue
            }
            let desktopNumber = spaceInfo.desktopNumber
            guard !monitor.displayUUID.isEmpty else {
                logger.warning("  Monitor '\(monitor.id, privacy: .public)': empty displayUUID, skipping")
                continue
            }

            if let currentID = currentSpaceByUUID[monitor.displayUUID], currentID == spaceInfo.spaceID {
                logger.info("  Monitor '\(monitor.id, privacy: .public)': already on desktop \(desktopNumber) (spaceID \(spaceInfo.spaceID)), skipping")
                continue
            }

            logger.info("  Monitor '\(monitor.id, privacy: .public)': will switch to desktop \(desktopNumber) (spaceID \(spaceInfo.spaceID))")
            desktopsToSwitch.append(desktopNumber)
        }

        guard !desktopsToSwitch.isEmpty else {
            logger.info("No desktops to switch, returning early")
            return
        }

        await postDesktopSwitches(desktopsToSwitch, trusted: trusted)
        logger.info("=== switchToGroup complete ===")
    }

    /// Switch specific displays to specific Spaces (used by gesture-follow). Requests whose display or
    /// Space is unknown are skipped. Uses the same keystroke mechanism as `switchToGroup`.
    @MainActor
    static func switchDisplays(_ requests: [SwitchRequest], monitors: [MonitorInfo]) async {
        var desktops: [Int] = []
        for request in requests {
            guard let monitor = monitors.first(where: { $0.displayUUID == request.displayUUID }),
                  let space = monitor.spaces.first(where: { $0.spaceID == request.spaceID }) else {
                logger.warning("switchDisplays: unknown display/space for request, skipping")
                continue
            }
            desktops.append(space.desktopNumber)
        }
        guard !desktops.isEmpty else { return }
        let trusted = AXIsProcessTrusted()
        if !trusted { AccessibilityManager.checkAndPrompt() }
        await postDesktopSwitches(desktops, trusted: trusted)
    }

    @MainActor
    private static func postDesktopSwitches(_ desktopsToSwitch: [Int], trusted: Bool) async {
        let desktopsDesc = desktopsToSwitch.map { String($0) }.joined(separator: ", ")
        logger.info("Desktops to switch: \(desktopsDesc, privacy: .public)")

        for desktopNumber in desktopsToSwitch {
            guard let mapping = KeyCodes.keyMapping(for: desktopNumber) else {
                logger.error("No key mapping for desktop \(desktopNumber)")
                continue
            }

            let flagsHex = String(mapping.flags.rawValue, radix: 16)
            logger.info("Desktop \(desktopNumber): keyCode=\(mapping.keyCode) flags=0x\(flagsHex, privacy: .public)")

            if trusted {
                // CGEvent keyboard simulation (requires Accessibility)
                let source = CGEventSource(stateID: .combinedSessionState)
                logger.info("CGEventSource created: \(source != nil)")

                let didPost = postKeystroke(source: source, keyCode: mapping.keyCode, flags: mapping.flags)
                logger.info("CGEvent postKeystroke result: \(didPost)")

                if !didPost {
                    logger.info("CGEvent failed, trying AppleScript fallback")
                    simulateViaAppleScript(keyCode: Int(mapping.keyCode), controlDown: true,
                                           optionDown: mapping.flags.contains(.maskAlternate))
                }
            } else {
                // No accessibility — go straight to AppleScript via System Events
                logger.info("Using AppleScript fallback (no accessibility)")
                simulateViaAppleScript(keyCode: Int(mapping.keyCode), controlDown: true,
                                       optionDown: mapping.flags.contains(.maskAlternate))
            }

            // Check if space actually changed after a brief wait
            try? await Task.sleep(for: .milliseconds(300))
            let newSpaces = getCurrentSpacePerDisplay()
            let newSpacesDesc = newSpaces.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            logger.info("Spaces after switch attempt: \(newSpacesDesc, privacy: .public)")
        }
    }

    private static func postKeystroke(source: CGEventSource?, keyCode: UInt16, flags: CGEventFlags) -> Bool {
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        logger.info("  keyDown event created: \(keyDown != nil)")
        logger.info("  keyUp event created: \(keyUp != nil)")

        guard let keyDown, let keyUp else {
            logger.error("  Failed to create CGEvent objects")
            return false
        }

        keyDown.flags = flags
        let flagsHex = String(flags.rawValue, radix: 16)
        logger.info("  Posting keyDown (keyCode=\(keyCode), flags=0x\(flagsHex, privacy: .public)) to .cghidEventTap")
        keyDown.post(tap: .cghidEventTap)

        usleep(50_000) // 50ms

        keyUp.flags = flags
        logger.info("  Posting keyUp to .cghidEventTap")
        keyUp.post(tap: .cghidEventTap)

        return true
    }

    private static func simulateViaAppleScript(keyCode: Int, controlDown: Bool, optionDown: Bool) {
        var modifiers: [String] = []
        if controlDown { modifiers.append("control down") }
        if optionDown { modifiers.append("option down") }
        let modifierClause = modifiers.isEmpty ? "" : " using {\(modifiers.joined(separator: ", "))}"

        let script = """
        tell application "System Events"
            key code \(keyCode)\(modifierClause)
        end tell
        """

        logger.info("  AppleScript: \(script, privacy: .public)")

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                let errorDesc = error.description
                logger.error("  AppleScript error: \(errorDesc, privacy: .public)")
            } else {
                logger.info("  AppleScript executed successfully")
            }
        } else {
            logger.error("  Failed to create NSAppleScript")
        }
    }

    static func getCurrentSpacePerDisplay(connection: Int32 = CGSMainConnectionID()) -> [String: UInt64] {
        guard let displays = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            logger.error("CGSCopyManagedDisplaySpaces returned nil")
            return [:]
        }

        var result: [String: UInt64] = [:]
        for display in displays {
            guard let uuid = display["Display Identifier"] as? String,
                  let currentSpace = display["Current Space"] as? [String: Any],
                  let spaceID = currentSpace["id64"] as? UInt64
            else { continue }
            result[uuid] = spaceID
        }
        return result
    }
}
