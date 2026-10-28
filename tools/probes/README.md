# Probes

Small, standalone Swift programs used to answer capability questions (see the
`investigation` issues). They are not part of the app. Build each with `swiftc`
from the Command Line Tools; no Xcode project needed. Output goes to `/tmp`.

| File | Issue | Safe during normal use? |
|---|---|---|
| `spaces_dump.swift` | - | Yes, read-only. Prints displays and Space IDs. |
| `window_move_probe.swift` + `probe_window_helper.swift` | #6 | Briefly shows a throwaway window; does not switch Spaces. |
| `self_move_control.swift` | #6 | Same, control run. |
| `snapshot_cost.swift` | #2 | Yes, read-only. Times a full window/Space snapshot. |
| `space_change_probe.swift` | #4 | Yes, read-only. Logs Space changes and which display changed. |
| `unplug_logger.swift` | #1, #3 | Yes, passive. Records display events and window/Space snapshots (no titles). |
| `direct_switch_probe.swift` | #5 | **Briefly switches a display's Space and restores it.** Run only when ready. |
| `ax_probe.swift` | #6 | Needs Accessibility for the host terminal. Briefly shows a throwaway window, moves it across displays by AX position. Does not switch Spaces. |

```
swiftc -O spaces_dump.swift -o /tmp/spaces_dump
swiftc -O probe_window_helper.swift -o /tmp/probe_window_helper
swiftc -O window_move_probe.swift -o /tmp/window_move_probe
swiftc -O self_move_control.swift -o /tmp/self_move_control
swiftc -O ax_probe.swift -o /tmp/ax_probe
/tmp/window_move_probe --target <spaceID> [--cross-display]
```

Redact window titles and display UUIDs before pasting probe output anywhere public.
