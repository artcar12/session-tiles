# Session Tiles

A floating, always-on-top macOS panel with one tile per running Claude for Mac (desktop app, Code tab)
session, colored by status. Clicking a tile opens that session in the Claude app.

- **Red**: `waiting`, blocked on you (shows `waitingFor`, e.g. "permission prompt")
- **Amber**: `idle`, waiting for you to type
- **Blue**: `busy`, the model is working
- **Gray**: a status value this app doesn't recognise (shown as-is)

Each tile shows the session name, the project (repo name; `.claude/worktrees/<x>` collapses to the repo),
and how long it has been in its current state. Order: pinned tiles first, then waiting (oldest first), idle, busy. All filtering lives in
`VisibilityRules.swift`.

## Controls and pins

A strip at the bottom of the panel (hide it with **Show Controls** in the menu-bar menu) holds:

- **SHOW ALL** switch: shows every live session, ignoring the other two controls. While off, its readout
  says how many sessions the filters are hiding.
- **STATUS** knob: ANY / WAIT / IDLE / BUSY. Click to turn, Option-click to turn back, scroll, or drag
  up/down.
- **STANDBY** fader: how long idle sessions stay visible, from 5m to 24h, or ∞ to keep them all.
  Default 1h. Click, drag or scroll. Greyed out while it has no effect (SHOW ALL on, or the knob on WAIT
  or BUSY).
- **SKIN** button: pops up the list of skins.

Pin a tile with the pin in its top-right corner (shows on hover) or from its right-click menu. Pinned
tiles ignore every filter and sort first. If a pinned session's process ends, its tile stays as a gray
**offline** tile counting time since it was last seen; clicking it still opens the session in Claude.
Unpin it to remove it. Pins and control settings are remembered.

The app runs as a menu-bar extra with no Dock icon. The menu-bar item toggles the panel and quits the
app; its icon shows a count when any session is waiting. Drag the panel by its background. It
remembers its size and position.

## Skins

Pick a skin with the **SKIN** button at the right of the control strip, by right-clicking an empty part
of the panel, or from the menu-bar menu (**Skin ▸**). It switches live and is remembered.

- **Classic**: flat rounded tiles over the system blur; follows light/dark mode.
- **DJ Deck**: backlit rubber pads on a black deck. Waiting pads strobe, busy pads run an EQ meter,
  idle pads sit dimly lit. Times read like a track clock (`04:07`).
- **Starship Console**: chamfered, outlined stations with glowing LEDs, scanlines and monospaced
  readouts. Waiting stations raise a red alert, busy ones run an LED chase, idle ones show STANDBY.

- **Cyberpunk**: neon noir. Rainy black-violet night, clipped-corner tiles outlined in glowing neon tubes,
  kanji status tags. Waiting tiles buzz like a failing sign with a pink/cyan split title, busy ones run a
  data chase.
- **Medieval Hall**: heraldic banners on a stone wall, serif type, gold trim. Waiting banners are lit by a
  flickering torch (a summons), busy ones are at work, idle ones hang dim at rest.
- **Reactor Control Room**: 1970s control panel in green enamel. Each session is an instrument module with
  an engraved label plate, an indicator lamp and an analog dial: flashing red SCRAM lamp and a pegged
  needle when waiting, green RUN lamp and a hunting needle when busy, amber STBY when idle.

Only Classic follows the system appearance. Reactor is always light; the others are always dark. All looping animations pause when
macOS Reduce Motion is on.

### Adding a skin

1. Add `Sources/SessionTiles/Skins/<Name>Skin.swift` with a type conforming to `Skin` (see `Skin.swift`):
   grid metrics, chrome colors and font, and `background()`, `header(_:)` and `tile(_:_:)` views.
   `ClassicSkin.swift` is the smallest example.
2. Add a case to `SkinID` with its display name.

Skins only draw. Data, ordering, visibility rules and clicks stay shared in `TilesView`/`TileButton`.

**Animations:** use the Core Animation helpers in `LayerEffects.swift` (`BlinkingFill`, `.blink()`,
`LEDChase`, `LevelMeter`, `SwingingNeedle`, and `Flicker` patterns via `.flicker()` or
`BlinkingFill(flicker:)`) for anything that loops. They run in the system render server and keep the panel
at about 1-3% CPU. Looping animations driven from SwiftUI (`phaseAnimator`, `repeatForever`, a fast
`TimelineView`) re-run layout for the whole grid each frame and cost 15-30% CPU for a few tiles.

## Requirements

macOS 14+, Swift 5.9+ toolchain (Xcode or Command Line Tools). No Xcode project is needed.

## Build and run

```bash
./build.sh
```

```bash
open build/SessionTiles.app
```

`./build.sh debug` builds a debug binary instead. Copy `build/SessionTiles.app` to `/Applications` if
you want to keep it around (e.g. add it to Login Items).

## How it works

Every running Claude Code process writes `~/.claude/sessions/<pid>.json` (an undocumented internal
format). The app:

- watches the folder with a DispatchSource and also polls every 1.5s, because files are rewritten in place;
- keeps files with `entrypoint == "claude-desktop"` whose `pid` is alive (`kill(pid, 0)`), and whose
  `procStart` matches the process's real start time when present, so a reused pid doesn't resurrect a
  stale file;
- opens a session with `claude://claude.ai/epitaxy/<hostSessionId>`.

If the folder can't be read, the panel shows a red error instead of tiles. If a live session's file fails
to parse on two consecutive reads, an orange banner names the file(s) above the tiles that did parse.

## Debugging

- `./list-live.py` lists live desktop sessions straight from the files, independently of the app.
  `./list-live.py --visible` prints them in tile order with the default filter (idle > 1h hidden), as
  TSV; it doesn't know about pins or the panel's controls.
- `SESSION_TILES_SNAPSHOT=/tmp/p.png build/SessionTiles.app/Contents/MacOS/SessionTiles` writes the
  panel to `/tmp/p.png` and the visible tiles to `/tmp/p.png.txt` (same TSV as `list-live.py --visible`)
  every 2s, so `diff <(./list-live.py --visible) /tmp/p.png.txt` checks the panel against the files
  (with default controls and no pins).
  The PNG is a real window-server capture of the app's own window, so it needs no Screen Recording
  permission and includes animations mid-flight.
- Switch skins without the menu: `defaults write com.arthurcarroll.SessionTiles skin starship`
  (`classic`, `djDeck`, `starship`, `cyberpunk`, `medieval`, `reactor`), then relaunch.
- `SESSION_TILES_DIR=/some/dir` reads sessions from another folder (for testing error states).

## Cross-platform checks

`verify/` holds read-only scripts for checking the session files on other platforms before porting:
`check-sessions.py` (Linux and macOS) and `check-sessions.ps1` (Windows; untested so far). Each lists
every session file with liveness and start-time checks, reports field names with `--fields` / `-Fields`,
and prints status changes with `--watch TEXT` / `-Watch TEXT`.

## License

MIT. See `LICENSE`.
