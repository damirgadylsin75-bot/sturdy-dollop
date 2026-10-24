"""Open Cloud helper: run Luau headlessly on a real Roblox server, or upload a place version.
Prints one JSON object. Stdlib only, Python 3.9+.

Adapted from https://github.com/m4bwav/roblox-agent (skill: roblox-agent-cloud).

    python rbx_cloud.py run --universe U --place P [--version V] --script FILE [--timeout 300]
    python rbx_cloud.py publish --universe U --place P --file game.rbxl [--type Saved|Published] [--yes]
    python rbx_cloud.py <command> ... --dry-run      (print the request without sending it)

The API key is read from the ROBLOX_API_KEY environment variable, never from the
command line, and is never printed. run needs luau-execution-session write+read
scopes; publish needs universe-places write. Exit 0 = ok, 1 = task/API failure,
2 = usage error.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = os.environ.get("ROBLOX_API_BASE", "https://apis.roblox.com").rstrip("/")
TERMINAL = {"COMPLETE", "FAILED", "CANCELLED"}
POLL_SECONDS = float(os.environ.get("RBX_CLOUD_POLL", "3"))


def request(method, url, key, body=None, content_type="application/json"):
    data = None
    headers = {"x-api-key": key}
    if body is not None:
        data = body if isinstance(body, bytes) else json.dumps(body).encode("utf-8")
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read().decode("utf-8", "replace")
            return r.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            payload = json.loads(raw)
        except ValueError:
            payload = {"body": raw[:2000]}
        return e.code, payload
    except (urllib.error.URLError, OSError) as e:
        return 0, {"error": str(e)}


def out(obj, code=0):
    print(json.dumps(obj, indent=2))
    return code


def task_url(a):
    v = "/versions/%s" % a.version if a.version else ""
    return "%s/cloud/v2/universes/%s/places/%s%s/luau-execution-session-tasks" % (BASE, a.universe, a.place, v)


def cmd_run(a, key):
    script = Path(a.script)
    if not script.is_file():
        return out({"ok": False, "error": "script not found: %s" % script}, 2)
    body = {"script": script.read_text(encoding="utf-8"), "timeout": "%ss" % a.timeout}
    url = task_url(a)
    if a.dry_run:
        return out({"ok": True, "dry_run": True, "method": "POST", "url": url,
                    "body": {"script": "<%d characters from %s>" % (len(body["script"]), script.name),
                             "timeout": body["timeout"]}}, 0)
    status, task = request("POST", url, key, body)
    if status != 200 or "path" not in task:
        return out({"ok": False, "stage": "create", "http": status, "response": task}, 1)
    path = task["path"]
    t0 = time.time()
    while task.get("state") not in TERMINAL:
        if time.time() - t0 > a.timeout + 120:
            return out({"ok": False, "stage": "poll", "error": "gave up waiting", "path": path, "state": task.get("state")}, 1)
        time.sleep(POLL_SECONDS)
        status, polled = request("GET", "%s/cloud/v2/%s" % (BASE, path), key)
        if status != 200:
            return out({"ok": False, "stage": "poll", "http": status, "response": polled, "path": path}, 1)
        task = polled
    state = task.get("state")
    result = {"ok": state == "COMPLETE", "path": path, "state": state,
              "results": (task.get("output") or {}).get("results"), "error": task.get("error")}
    status, logs = request("GET", "%s/cloud/v2/%s/logs" % (BASE, path), key)
    lines = []
    if status == 200:
        for entry in logs.get("luauExecutionSessionTaskLogs", []):
            lines.extend(entry.get("messages", []))
            for m in entry.get("structuredMessages", []):
                lines.append("%s: %s" % (m.get("messageType", ""), m.get("message", "")))
    result["logs"] = lines[-200:]
    return out(result, 0 if result["ok"] else 1)


def cmd_publish(a, key):
    f = Path(a.file)
    if not f.is_file() or f.suffix.lower() not in (".rbxl", ".rbxlx"):
        return out({"ok": False, "error": "need an existing .rbxl or .rbxlx file: %s" % f}, 2)
    if a.type == "Published" and not a.yes:
        return out({"ok": False, "error": "Published makes this version live for players; rerun with --yes once the user agreed"}, 2)
    url = "%s/universes/v1/%s/places/%s/versions?versionType=%s" % (BASE, a.universe, a.place, a.type)
    ctype = "application/xml" if f.suffix.lower() == ".rbxlx" else "application/octet-stream"
    if a.dry_run:
        return out({"ok": True, "dry_run": True, "method": "POST", "url": url, "content_type": ctype,
                    "bytes": f.stat().st_size}, 0)
    status, resp = request("POST", url, key, f.read_bytes(), ctype)
    ok = status == 200 and "versionNumber" in resp
    return out({"ok": ok, "http": status, "versionType": a.type, "versionNumber": resp.get("versionNumber"),
                "response": None if ok else resp}, 0 if ok else 1)


def main(argv):
    p = argparse.ArgumentParser(description="Open Cloud helper: run Luau on Roblox servers / upload place versions")
    sub = p.add_subparsers(dest="cmd")
    helps = {"run": "run a Luau script on a Roblox server and print its results and logs",
             "publish": "upload a .rbxl or .rbxlx file as a new place version"}
    for name in ("run", "publish"):
        s = sub.add_parser(name, help=helps[name], description=helps[name])
        s.add_argument("--universe", required=True)
        s.add_argument("--place", required=True)
        s.add_argument("--key-env", default="ROBLOX_API_KEY")
        s.add_argument("--dry-run", action="store_true")
        if name == "run":
            s.add_argument("--version")
            s.add_argument("--script", required=True)
            s.add_argument("--timeout", type=int, default=300)
        else:
            s.add_argument("--file", required=True)
            s.add_argument("--type", choices=["Saved", "Published"], default="Saved")
            s.add_argument("--yes", action="store_true")
    a = p.parse_args(argv)
    if not a.cmd:
        p.print_help()
        return 2
    if not (a.universe.isdigit() and a.place.isdigit()):
        return out({"ok": False, "error": "--universe and --place must be numeric ids"}, 2)
    key = os.environ.get(a.key_env, "")
    if a.dry_run:
        key = ""
    elif not key:
        return out({"ok": False, "error": "missing API key in env var %s" % a.key_env}, 2)
    if a.cmd == "run":
        return cmd_run(a, key)
    return cmd_publish(a, key)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
