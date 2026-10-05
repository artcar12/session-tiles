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

- **SHOW ALL** switch: shows every live session, ignoring the status knob and standby fader. While off, its
  readout says how many sessions the filters are hiding.
- **PINNED** switch: shows or hides pinned tiles, offline ones included. SHOW ALL still shows live pinned
  sessions while it's off.
- **DORMANT** switch: also shows sessions from the Claude app's sidebar that have no running process, as
  dimmed tiles (most recent first, after the live ones). They follow the STANDBY window and show for the
  ANY and IDLE knob positions; with SHOW ALL on, every non-archived one shows. Clicking one reopens it in
  Claude. While off, its readout says how many it would add.
- **STATUS** knob: ANY / WAIT / IDLE / BUSY. Click to turn, Option-click to turn back, scroll, or drag
  up/down.
- **STANDBY** fader: how long idle and dormant sessions stay visible, from 5m to 7d, or ∞ to keep them all.
  Default 1h. Click, drag or scroll. Greyed out while it has no effect (SHOW ALL on, or the knob on WAIT
  or BUSY).
- **SKIN** button: pops up the list of skins.

Pin a tile with the pin in its top-right corner (shows on hover) or from its right-click menu. Pinned
tiles ignore every filter (except the PINNED switch) and sort first. A pinned idle tile gets its own color
in every skin (violet in most, green in Cyberpunk and Arcade, purpure in Medieval, a blue lamp in Reactor),
so it stands apart from ordinary idle ones. If a pinned session's process ends, its tile stays as a gray
**offline** tile counting time since it was last seen; clicking it still opens the session in Claude.
Unpin it to remove it. Pins and control settings are remembered.

Archive a tile with the box icon beside the pin (shows on hover) or **Archive** in its right-click menu.
This sets the session's archived flag in the Claude app's own record, so the panel keeps no separate
hidden list: an archived session disappears from the panel (pinned and dormant ones too) and comes back
whenever Claude clears the flag, for example when you use the session again. With SHOW ALL on, archived
live sessions still show, dimmed, with an undo icon to unarchive them. Claude reads the flag only at
startup, so its sidebar catches up the next time Claude restarts.

If you run more than one Claude instance side by side (say a second account started with
`--user-data-dir=~/Library/Application Support/Claude-personal`), each tile gets a small letter badge on
its top-left corner saying which one the session belongs to. The letter is the initial of the data folder's
suffix (`Claude-personal` → **P**); the default `Claude` folder gets **D**. Set your own letters with
`defaults write com.arthurcarroll.SessionTiles accountBadges -dict Claude W Claude-personal P`. With one
instance there are no badges. A live session the instance hasn't recorded yet has no badge until it does.

The app runs as a menu-bar extra with no Dock icon. The menu-bar item toggles the panel and quits the
app; its icon shows a count when any session is waiting. Drag the panel by its background. It
remembers its size and position.

## Skins

Pick a skin with the **SKIN** button at the right of the control strip, by right-clicking an empty part
of the panel, or from the menu-bar menu (**Skin ▸**). It switches live and is remembered.

- **Classic**: flat rounded tiles over the system blur; follows light/dark mode.
- **DJ Deck**: backlit rubber pads on a black deck. Waiting pads strobe, busy pads run an EQ meter,
  idle pads sit dimly lit. Times read like a clock, hours and minutes (`01:04`).
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

- **Retro Arcade**: 80s cabinet CRT with scanlines and a pixel starfield, stepped pixel-art tile corners
  and 8x8 sprites. Waiting tiles blink INSERT COIN, idle ones say PRESS START, busy ones are NOW PLAYING,
  and an ended pinned session is GAME OVER.

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

Only running sessions write those files. For dormant tiles the app also reads the Claude app's own record
of every Code-tab session, `~/Library/Application Support/Claude*/claude-code-sessions/<id>/<id>/local_*.json`
(title, cwd, `lastActivityAt`, `isArchived`; also undocumented), polled every 5s. Every `Claude*` data
folder is read, so a second instance's sessions show up too; which folder a record sits in is what the
account badges go by. If those folders are missing or their format changes, dormant tiles and badges just
don't appear.

Archiving edits that record directly: it swaps the single `"isArchived":false` for `true` (or back),
writes a sibling file with the original permissions and renames it over, and refuses with an alert if the
file doesn't contain exactly one such flag. It doesn't do anything else Claude's own Archive might.

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
  (`classic`, `djDeck`, `starship`, `cyberpunk`, `medieval`, `reactor`, `arcade`), then relaunch.
- `SESSION_TILES_DIR=/some/dir` reads sessions from another folder (for testing error states).
  `SESSION_TILES_APP_DIR=/some/dir` does the same for the Claude app's session records (dormant tiles).

## Cross-platform checks

`verify/` holds read-only scripts for checking the session files on other platforms before porting:
`check-sessions.py` (Linux and macOS) and `check-sessions.ps1` (Windows; untested so far). Each lists
every session file with liveness and start-time checks, reports field names with `--fields` / `-Fields`,
and prints status changes with `--watch TEXT` / `-Watch TEXT`.

## License

MIT. See `LICENSE`.
