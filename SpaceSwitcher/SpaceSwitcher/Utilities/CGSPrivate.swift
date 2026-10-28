import CoreGraphics

// MARK: - Private CoreGraphics SPI (read-only Space queries)
//
// These symbols are not in public headers. They are only used to *read* Space layout and the active
// Space; this app never uses private calls to move windows or to switch Spaces:
//  - Moving other processes' windows with CGSAddWindowsToSpaces / CGSMoveWindowsToManagedSpace is a
//    silent no-op on current macOS without SIP-dependent injection (verified on macOS 26, issue #6).
//  - CGSManagedDisplaySetCurrentSpace changes the "current Space" bookkeeping but does not post
//    NSWorkspace.activeSpaceDidChangeNotification or hide the previous Space's windows (issue #5).
// Spaces are switched with the native "Switch to Desktop N" keyboard shortcuts instead.

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ connection: Int32) -> Int
