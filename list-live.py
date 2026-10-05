#!/usr/bin/env python3
"""List live Claude desktop sessions from ~/.claude/sessions, independently of the app.

  ./list-live.py            all live desktop sessions
  ./list-live.py --visible  only those the default filter shows (hides idle > 1h; ignores pins), in tile order, as TSV
"""
import glob, json, os, sys, time

now = time.time() * 1000
rows = []
for path in glob.glob(os.path.expanduser("~/.claude/sessions/*.json")):
    try:
        d = json.load(open(path))
        os.kill(int(d["pid"]), 0)
    except PermissionError:
        pass
    except Exception:
        continue
    if d.get("entrypoint") != "claude-desktop":
        continue
    rows.append(d)

def project(cwd):
    return os.path.basename(cwd.split("/.claude/worktrees/")[0])

rank = {"waiting": 0, "idle": 1, "busy": 2}
if "--visible" in sys.argv:
    rows = [d for d in rows if not (d.get("status") == "idle" and now - d["statusUpdatedAt"] > 3600_000)]
    rows.sort(key=lambda d: (rank.get(d.get("status"), 3), d.get("statusUpdatedAt", 0), d["hostSessionId"]))
    for d in rows:
        print("\t".join([d.get("status", "?"), project(d.get("cwd", "")), d.get("name") or os.path.basename(d.get("cwd", "")),
                         d.get("waitingFor", ""), d["hostSessionId"]]))
else:
    for d in sorted(rows, key=lambda d: d.get("statusUpdatedAt", 0)):
        age = (now - d.get("statusUpdatedAt", now)) / 60000
        print(f"{d.get('status','?'):8} {age:7.1f}m  {project(d.get('cwd','')):20} {d.get('name','')!s:50} {d.get('waitingFor','')} {d.get('hostSessionId','')}")
