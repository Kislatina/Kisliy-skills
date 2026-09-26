---
name: offstage
description: Run a macOS app on a hidden virtual display, look at it, and drive it — without ever touching the user's screen, cursor, or focus. Creates an off-screen display the user cannot see, launches a store-isolated instance onto it, and keeps its windows there; you screenshot, read the accessibility tree, click, type, use menus and shortcuts, all delivered straight to the app so the real pointer never moves and the front app never changes. Use when you need to verify or operate a GUI while the user keeps working — "run it and show me", "screenshot the app", "click through the settings", "check it looks right", or any UI check that must not steal the screen. Every app it launches is flagged as an agent run (OFFSTAGE=1, NULL_AGENT=1), so an app that reads the flag — every Null app does — marks its windows and Dock tile red while you drive it, and the user can always tell your instance from their own.
---

# Offstage

The screen belongs to the user. They are working on it right now — typing,
switching windows, in a call. **Offstage never touches that screen.** It builds a virtual display the user cannot see, runs the app there,
and delivers every click and keystroke straight to that app's process. The real
cursor never moves, the front-most app never changes, nothing flashes. You can
drive a full GUI while the user keeps working, and they never know.

It not only screenshots, it *operates* the
app — accessibility tree, clicks, typing, menus, shortcuts, drag, scroll,
multiple windows, multiple apps, multiple parallel sessions.

## The tool

```bash
offstage=~/.claude/skills/offstage/bin/offstage
```

Every command prints exactly **one JSON object**. `"ok": false` carries an
`"error"`. The daemon **auto-starts** on the first command that needs it, so you
can go straight to `launch`.

If `offstage` is missing, build it: `~/.claude/skills/offstage/build.sh`.

## How it works (why it is safe)

- A **virtual display** (private CoreGraphics API) is created and parked
  diagonally off the corner of the real screen. The user's screen recording and
  arrangement are untouched; the user sees nothing.
- The app is launched **hidden**, its window moved onto the virtual display
  *before* it is unhidden, and a **warden** keeps every window of every session
  on the virtual display — a window that tries to open on the user's screen is
  yanked back within a frame.
- Input is posted with `CGEventPostToPid`: it goes **to the app process**, not
  through the system event stream. So the physical cursor stays where the user
  left it, the keyboard focus stays in the user's app, and clicks are routed to
  the right window even though it is off-screen.
- A **focus guard** hands the front-most role straight back if a launched app
  ever tries to activate itself.

Net effect: **the user can keep working the entire time.**

## The normal flow

```bash
offstage=~/.claude/skills/offstage/bin/offstage

# 1. Launch (daemon auto-starts). Isolated store, own HOME, hidden.
$offstage launch "/Users/kisliy/NullEcoSystem/NullTerm/build/NullTerm.app" --id term

# 2. Look.
$offstage shot term --label "before"
#    → read the "small" path with the Read tool (Retina PNG downscaled ~1280px).

# 3. Understand what is on screen (roles, titles, ids, frames — clickable coords).
$offstage tree term

# 4. Drive it — by element (robust) or by coordinate.
$offstage click term --desc "New tab"          # AX selector: no pixel-hunting
$offstage type  term "echo hello"
$offstage key   term enter
$offstage menu  term View "Enter Full Screen"  # menu bar of the background app

# 5. Look again, then quit only what you launched.
$offstage shot term --label "after"
$offstage quit term
```

Read the `small` screenshot with the Read tool. `path` is the full-resolution
Retina original — reach for it only to read fine detail.

## Every launch is signed

The user is working an arm's length away while you drive a GUI. The one thing
they must never have to wonder is whether the window that just appeared is
theirs or yours. So every app offstage launches gets the flag in its
environment, whether or not you asked for it:

| | |
| --- | --- |
| `OFFSTAGE=1` | started by offstage |
| `OFFSTAGE_SESSION=<id>` | which session it belongs to |
| `NULL_AGENT=1` | **an agent owns this run** |

An app that reads the flag says so on itself. Every app in the Null ecosystem
does, through NullKit: the mark in its windows and its Dock tile wear a red
`agent` plate on the bottom-right corner — the same stamp that reads amber `DEV`
for a copy out of `build/`, with the agent's red outranking it. Nothing to
remember at the call site: the launch cannot happen without the flag.

Two consequences for you:

- **Use it as proof of what you are looking at.** A frame with the red `agent`
  plate is your instance. A clean mark, or an amber `DEV` in a frame you did not
  launch, means you are looking at the user's own copy — re-check the session
  before you act on it.
- **Do not take the flag off on your own.** `--env NULL_AGENT=0`, or
  `--env NULLKIT_CHANNEL=installed` to make a screenshot look "clean", turns an
  agent's window into something indistinguishable from the user's. If a clean
  frame is genuinely needed (promo material, docs), say that the stamp is there
  and let the user decide — do not quietly strip it.

Launching a Null app **outside** offstage — `open`, a build script, a direct
binary — carries no flag by itself: `open` hands the app launchd's environment,
not your shell's. Pass it explicitly, and keep doing it whenever you start an
app on the user's behalf:

```bash
open --env NULL_AGENT=1 -a NullOne                         # bundle, via LaunchServices
NULL_AGENT=1 ./build/NullOne.app/Contents/MacOS/NullOne    # or the binary directly
```

Apps outside the ecosystem ignore all of this — the flag is still in their
environment, they simply have nothing to draw with it.

## Commands

| | |
| --- | --- |
| `launch <App.app> [--id NAME]` | New store-isolated instance on the virtual display, flagged as an agent run. Prints pid, isolation, windows. |
| `ls` / `status` | Running sessions / + permissions, display, user's front app. |
| `quit <session>` / `quit --all` | Terminate only what offstage launched. `--purge` also drops its isolated store. |
| `shot <session>` | Screenshot the app (all its windows, popovers, sheets). `--window ID`, `--display`, `--region X Y W H`, `--scale 1`. |
| `tree <session>` | Accessibility tree: role, title, id, value, **frame** and a `#path`. The map you act on. `--all`, `--role AXButton`, `--all-windows`, `--json`. |
| `find <session> --title/-–id/--desc/--value` | Locate one element; returns its center coordinate and AX actions. |
| `click <session> …` | By selector (`--desc "Save"`) **or** coordinate (`X Y`). `--double`, `--right`, `--mod cmd`. |
| `press <session> --id … [--action AXPress]` | Fire an AX action directly — no mouse, most robust for buttons/toggles. |
| `set <session> --id … --value "text"` | Set a field's value through AX (instant, no per-key typing). |
| `focus <session> --id …` | Give an element keyboard focus. |
| `type <session> "text"` | Type into the focused control. |
| `key <session> cmd+n [enter …]` | Key chords. ⌘-chords are resolved through the **menu bar** so they work on the inactive app; `--raw` forces a posted event. |
| `menu <session>` / `menu <session> File "New"` | List enabled menu items with their shortcuts / press one by path. |
| `scroll <session> X Y --dy -300` · `drag <session> X Y --to X Y` · `resize <session> WxH` | Pointer gestures + window sizing. |
| `wait <session> [sec]` · `log <session>` | Settle / read the app's own os_log output. |

## Coordinates

`shot` and `tree` report frames in **points relative to the window's
top-left** — pass those straight back to `click`/`scroll`/`drag`. Three systems,
switchable per command:

- default — relative to the main window's top-left.
- `--image` — **pixels of the last screenshot** of that session (what you see in
  the Read'd PNG; the tool divides by the Retina scale for you).
- `--abs` — global points.

**Prefer selectors over pixels.** `--desc`, `--title`, `--id`, or a `#path` from
`tree` survive layout changes and Retina scaling; a hard-coded pixel does not.
Use coordinates only for canvas-like surfaces with no accessibility.

## Isolation — and the one tradeoff

By default each session runs an **APFS clone** of the bundle with its own bundle
id (`…​.offstage.<session>`), so its **UserDefaults, saved window frames and
Application Support never touch the user's real copy of the app**. Copy-on-write,
so it is nearly free. State persists across relaunches of the same `--id` until
`--fresh` (wipe first) or `quit --purge`.

The clone has a **different bundle id, so it does not inherit the real app's TCC
grants** (Screen Recording, Microphone, Camera, Automation, Full Disk Access).
For an app that needs one of those to function (e.g. a screen-capture or
dictation app), launch with **`--as-is`**: it runs the original bundle and keeps
the grant, at the cost of **sharing UserDefaults with the user's installed
copy**. `--shared-home` likewise uses the real `$HOME`.

Rule of thumb: **default (clone)** for anything whose state you don't want to
pollute; **`--as-is`** for an app that would otherwise sit at a permission wall.

## Putting the right screen up

Many surfaces sit behind a click or a launch flag. Two ways in:

- Drive to it: `click`/`menu`/`key` after launch.
- Launch straight into it with the app's own env hooks, e.g.
  `launch … --env NULLSPACE_SETTINGS=1 --env NULLSPACE_SETTINGS_TAB=canvas`.
  NullSpace documents ~35 `NULLSPACE_*` hooks in `NullSpace/CLAUDE.md`; other
  apps have their own — check the app's `CLAUDE.md`/README rather than guessing.
  Pass any with `--env K=V`, extra argv with `--arg`, files to open with
  `--open FILE`.

## Read the JSON

- `launch` → `windows[].onVirtualDisplay` must be `true` for each; `isolation`
  states clone vs as-is; `notes` flags anything unusual (e.g. a window that was
  slow to appear).
- `click`/`type`/`key` → `window` is the window the event was routed to; `0`
  with a `warning` means nothing of that app was under the point and the event
  was dropped — re-check coordinates against a fresh `shot`/`tree`.
- `shot` → `mainWindow.offsetInImage` locates the window inside the frame;
  `windows[]` lists everything captured.
- `status` → `permissions` (both must be true), `frontmost` (the user's app —
  should never be one of yours), the live session list.

## Parallel agents

The daemon is shared and serializes requests, and the virtual display holds any
number of sessions at once — so **parallel agents just use distinct `--id`s**;
no screen-wide lock is needed. If two agents pick
the same id, `launch` auto-suffixes the second (`term-2`). Quit only your own
sessions (`quit <id>`), not `--all`, when others may be running.

## Red lines

- **Never `pkill`/`killall`/`pgrep` by name.** Swift build processes carry the
  app's path in their command line and match. `quit` signals only pids offstage
  launched, and only instances it can prove are isolated.
- **The frame shows only the app, on the hidden display** — never the user's
  desktop. Even so, keep screenshots in the cache dir; do not attach them to a
  PR or publish them without asking.
- **Do not disguise your own instance.** The agent flag goes on every launch and
  the red `agent` plate goes with it. Never strip it to make a frame look like
  the user's own run.
- **Do not grant TCC programmatically.** If `status` shows a permission missing,
  only the seated user can turn it on (System Settings → Privacy & Security).
  Never trigger the prompt yourself — you cannot answer it.
- **"Nothing changed" is not a stale build.** The user runs their installed
  copy; offstage runs the build you point it at. Re-read what you shipped.

## When it refuses

| JSON says | Do this |
| --- | --- |
| `daemon is not running` after a build | The build script stops the daemon; the next command auto-starts it. Just re-run. |
| `missing permissions` | `status` shows which. The user grants Screen Recording **and** Accessibility to *this terminal app*, once. |
| `CGVirtualDisplay … not available` | The private API changed in this macOS; offstage can't run here. |
| `no shareable windows yet` / no window | Give it a moment (`wait`), or it is a menu-bar/on-demand app with no window until triggered. For a **sandboxed document app** (e.g. TextEdit) retry with `--no-hide`. |
| a window shows `onVirtualDisplay: false` | The warden will pull it back within a tick; re-`shot`. Report it if it persists. |

## When you do not need this

If the app exposes a headless self-test or an off-screen render hook, use it —
faster and needs no display at all. Reach for offstage when the thing you must
see or operate only exists in a live, composited window.

<!-- offstage-skill v2 — every launch carries the agent flag -->
