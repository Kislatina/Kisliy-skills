# offstage

Run a macOS app on a **hidden virtual display**, screenshot it, and drive it —
without touching the user's screen, cursor, or keyboard focus. It operates the
UI instead of only photographing it, and never needs to borrow the real screen.

For agent-facing usage see `SKILL.md`. This file is for maintaining the tool.

## Layout

```
offstage/
  SKILL.md          agent instructions (the contract)
  README.md         this file
  build.sh          stop daemon → swift build → install → codesign
  bin/offstage      the installed universal-ish arm64 binary
  tool/             SwiftPM package (source of truth)
    Sources/offstage/
      main.swift        CLI arg parsing + command dispatch + daemon auto-start
      Client.swift      talks to the daemon; spawns it detached (posix_spawn+setsid)
      Socket.swift      newline-delimited JSON over a unix socket
      Daemon.swift      @MainActor: owns display + sessions, guards, dispatch
      VirtualDisplay.swift  CGVirtualDisplay* via the ObjC runtime; un-mirror + park
      Session.swift     one launched instance: launch/clone/observe/terminate
      Capture.swift     ScreenCaptureKit: photograph one app on the display
      Input.swift       CGEventPostToPid clicks/keys/scroll/drag, routed to a window
      AX.swift          Accessibility: tree walk, node model, element resolution
      Menu.swift        menu-bar reading + shortcut→item resolution
      Paths.swift       cache dirs + JSON helpers
```

## Build

```bash
~/.claude/skills/offstage/build.sh
```

It stops any running daemon first (overwriting a memory-mapped binary in place
gets it SIGKILLed), rebuilds release, copies to `bin/`, and re-signs ad-hoc.
The next `offstage` command auto-starts a fresh daemon.

## How it works

- **Virtual display**: `CGVirtualDisplayDescriptor/Settings/Mode/CGVirtualDisplay`
  reached through the ObjC runtime (private, but stable for years). Created with a
  fixed vendor/product/serial so macOS remembers its arrangement, then
  un-mirrored and parked one corner-pixel off the main display's bottom-right.
- **Launch**: `NSWorkspace.openApplication` with `createsNewApplicationInstance`,
  `activates=false`, `hides=true`. The window is parked on the display while
  still hidden, then unhidden. A two-phase wait plus an `AXObserver`
  (`kAXWindowCreated`) plus a 0.25 s warden tick keep every window on the display.
- **Agent flag**: the child environment always carries `OFFSTAGE=1`,
  `OFFSTAGE_SESSION=<id>` and `NULL_AGENT=1`. `Session.launch` writes all three
  before the caller's `--env` pairs, so no launch can happen without them. An app
  that reads the flag marks itself as an agent's run — NullKit draws a red
  `agent` plate on the app's mark and on its Dock tile, outranking the amber
  `DEV` a copy out of `build/` would otherwise wear.
- **Input**: `CGEventPostToPid` delivers to the process, so the real cursor and
  focus never move. Mouse events set two undocumented `CGEventField`s — `51`
  (target `CGWindowID`) and `146` (non-zero routing flag) — without which AppKit
  drops a posted event as "windowNumber 0". Keyboard events set field `51` too so
  window-scoped shortcuts resolve. ⌘-chords are pressed via the menu bar
  (`AXPress`) because an inactive app's `NSMenu` never sees a posted key
  equivalent.
- **Isolation**: default launch runs an APFS clone (`cp -c`) with bundle id
  `<orig>.offstage.<session>` and its own `$HOME`, so UserDefaults/window frames
  don't touch the user's real app. `--as-is` runs the original bundle (keeps TCC
  grants, shares defaults).

## Verified on macOS 26.5 (arm64)

Launch hidden, screenshot (Retina), AX tree, click by selector and by
image/relative/abs coordinate, type, ⌘-shortcuts via menu bar, `menu` press,
resize, multi-window warden, second app, **parallel sessions**, defaults
isolation (no leak into the real app), and **zero** real-cursor movement / focus
change under sustained input.

## Known limits

- Sandboxed document apps (TextEdit) may not create a window while hidden — use
  `--no-hide` (brief flash as the warden pulls the window over).
- Clones don't inherit TCC grants — use `--as-is` for apps that need Screen
  Recording / Mic / etc.
- Menu-bar / on-demand apps show no window until triggered — expected.
- Depends on the private `CGVirtualDisplay` API; a future macOS may remove it.

## Artifacts

State lives under `~/Library/Caches/offstage/`:
`offstage.sock`, `daemon.log`, `sessions/<id>/` (screenshots, per-session
`home/` and `app/` clone). Nothing is ever written into a project directory.
