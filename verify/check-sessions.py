#!/usr/bin/env python3
"""Read-only check of Claude Code session files (~/.claude/sessions) on Linux or macOS.

  python3 check-sessions.py               table of every session file
  python3 check-sessions.py --fields      every field name seen, vs the macOS reference
  python3 check-sessions.py --watch TEXT  print status changes of live sessions whose name,
                                          cwd or hostSessionId contains TEXT (Ctrl+C to stop)
  --dir PATH                              read another folder
"""
import argparse, glob, json, os, subprocess, sys, time

EXPECTED = {"pid", "sessionId", "cwd", "startedAt", "procStart", "version", "kind", "entrypoint",
            "hostSessionId", "name", "nameSource", "status", "updatedAt", "statusUpdatedAt",
            "messagingSocketPath", "waitingFor", "nameSince", "pidDomain", "peerProtocol", "peerFeatures"}


def default_dir():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    return os.path.join(base, "sessions")


def load(folder):
    out = []
    for path in sorted(glob.glob(os.path.join(folder, "*.json"))):
        try:
            with open(path) as f:
                out.append((os.path.basename(path), json.load(f), None))
        except Exception as e:
            out.append((os.path.basename(path), None, str(e)))
    return out


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except PermissionError:
        return True
    except Exception:
        return False


def real_start_utc(pid):
    """Process start as UTC asctime text, from ps (local time, 1 s precision)."""
    try:
        out = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True,
                             env={**os.environ, "LC_ALL": "C"}).stdout.strip()
        t = time.mktime(time.strptime(" ".join(out.split()), "%a %b %d %H:%M:%S %Y"))
        return time.asctime(time.gmtime(t))
    except Exception:
        return None


def same_start(proc_start, real):
    return proc_start is not None and real is not None and " ".join(proc_start.split()) == " ".join(real.split())


def age(ms):
    if not isinstance(ms, (int, float)):
        return "?"
    s = int(time.time() - ms / 1000)
    return f"{s}s" if s < 60 else f"{s // 60}m" if s < 3600 else f"{s // 3600}h{(s % 3600) // 60:02d}m"


def table(folder):
    rows = load(folder)
    print(f"folder: {folder}  ({len(rows)} json files)\n")
    for name, d, err in rows:
        if err:
            print(f"{name}: PARSE ERROR {err}")
            continue
        pid = d.get("pid")
        live = alive(pid) if pid is not None else False
        real = real_start_utc(pid) if live else None
        match = "-" if not live else ("yes" if same_start(d.get("procStart"), real) else f"NO (real {real})")
        print(f"{name}: live={live} startMatches={match}")
        for k in ("entrypoint", "status", "waitingFor", "name", "cwd", "hostSessionId", "procStart", "pidDomain",
                  "messagingSocketPath", "version"):
            if k in d:
                print(f"    {k:14} {d[k]}")
        print(f"    {'in state for':14} {age(d.get('statusUpdatedAt'))}")


def fields(folder):
    seen = {}
    for _, d, _ in load(folder):
        for k in (d or {}):
            seen[k] = seen.get(k, 0) + 1
    for k in sorted(seen):
        print(f"{k:22} {seen[k]:3} files  {'' if k in EXPECTED else 'NEW (not seen on macOS)'}")
    for k in sorted(EXPECTED - seen.keys()):
        note = "absent now (only present while waiting)" if k == "waitingFor" else "MISSING (seen on macOS)"
        print(f"{k:22}   0 files  {note}")


def watch(folder, text):
    last = {}
    print(f"watching {folder} for sessions matching {text!r}; Ctrl+C to stop", flush=True)
    while True:
        for name, d, err in load(folder):
            if err or not alive(d.get("pid", -1)):
                continue
            hay = " ".join(str(d.get(k, "")) for k in ("name", "cwd", "hostSessionId"))
            if text.lower() not in hay.lower():
                continue
            state = (d.get("status"), d.get("waitingFor"))
            if last.get(name) != state:
                last[name] = state
                lag = time.time() - d.get("statusUpdatedAt", 0) / 1000
                print(f"{time.strftime('%H:%M:%S')}  {name}  status={state[0]} waitingFor={state[1]}"
                      f"  (file says changed {lag:.1f}s ago)  {d.get('name', '')}", flush=True)
        time.sleep(0.25)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=default_dir())
    ap.add_argument("--fields", action="store_true")
    ap.add_argument("--watch", metavar="TEXT")
    a = ap.parse_args()
    if not os.path.isdir(a.dir):
        sys.exit(f"no such folder: {a.dir}")
    try:
        fields(a.dir) if a.fields else watch(a.dir, a.watch) if a.watch is not None else table(a.dir)
    except KeyboardInterrupt:
        pass
