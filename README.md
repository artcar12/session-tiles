# Session Tiles

A floating, always-on-top macOS panel with one tile per running Claude for Mac (desktop app, Code tab)
session, colored by status. Clicking a tile opens that session in the Claude app.

- **Red**: `waiting`, blocked on you (shows `waitingFor`, e.g. "permission prompt")
- **Amber**: `idle`, waiting for you to type
- **Blue**: `busy`, the model is working
- **Gray**: a status value this app doesn't recognise (shown as-is)

Each tile shows the session name, the project (repo name; `.claude/worktrees/<x>` collapses to the repo),
and how long it has been in its current state. Order: waiting (oldest first), then idle, then busy.
Idle sessions older than 1 hour are hidden (see `VisibilityRules.swift`, the only place filtering lives).

The app runs as a menu-bar extra with no Dock icon. The menu-bar item toggles the panel and quits the
app; its icon shows a count when any session is waiting. Drag the panel by its background. It
remembers its size and position.

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
  `./list-live.py --visible` prints them in tile order with the same 1-hour rule, as TSV.
- `SESSION_TILES_SNAPSHOT=/tmp/p.png build/SessionTiles.app/Contents/MacOS/SessionTiles` writes the
  panel to `/tmp/p.png` and the visible tiles to `/tmp/p.png.txt` (same TSV as `list-live.py --visible`)
  every 2s, so `diff <(./list-live.py --visible) /tmp/p.png.txt` checks the panel against the files.
  It needs no Screen Recording permission.
- `SESSION_TILES_DIR=/some/dir` reads sessions from another folder (for testing error states).
