# Probes

Small, standalone Swift programs used to answer capability questions (see the
`investigation` issues). They are not part of the app. Build each with `swiftc`
from the Command Line Tools; no Xcode project needed. Output goes to `/tmp`.

| File | Issue | Safe during normal use? |
|---|---|---|
| `spaces_dump.swift` | - | Yes, read-only. Prints displays and Space IDs. |
| `window_move_probe.swift` + `probe_window_helper.swift` | #6 | Briefly shows a throwaway window; does not switch Spaces. |
| `self_move_control.swift` | #6 | Same, control run. |

```
swiftc -O spaces_dump.swift -o /tmp/spaces_dump
swiftc -O probe_window_helper.swift -o /tmp/probe_window_helper
swiftc -O window_move_probe.swift -o /tmp/window_move_probe
swiftc -O self_move_control.swift -o /tmp/self_move_control
/tmp/window_move_probe --target <spaceID> [--cross-display]
```

Redact window titles and display UUIDs before pasting probe output anywhere public.
