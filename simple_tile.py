#!/usr/bin/env python3
"""Handle one openwindow event. Omarchy owns the UI and event subscription.

Only newly opened windows trigger automatic overflow moves. Manually moving
windows (e.g. with Super+Shift+2) intentionally overrides the workspace window
limit, preserving full user control over window layout.
"""

from __future__ import annotations

import argparse
from collections import Counter
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time

PLUGIN_ID = "ubruckhaus.simple-tile"


def normalize_addr(value):
    address = str(value).lower().removeprefix("0x")
    if not re.fullmatch(r"[0-9a-f]+", address):
        raise ValueError("invalid window address")
    return "0x" + address


def is_tiled(client):
    ws = client.get("workspace", {}).get("id", 0)
    return (type(ws) is int and ws > 0 and client.get("mapped", False)
            and not client.get("floating", False)
            and not client.get("fullscreen", 0)
            and not client.get("hidden", False))


def tiling_counts(clients):
    return Counter(c["workspace"]["id"] for c in clients if is_tiled(c))


def pick_target_ws(workspaces, counts, current_ws_id, max_windows, workspace_caps=None):
    """Scan forward on this monitor; never reuse another monitor's ID."""
    if type(current_ws_id) is not int or current_ws_id <= 0:
        return None
    source = next((w for w in workspaces if w["id"] == current_ws_id), None)
    if source is None:
        return None
    same_monitor = sorted(w["id"] for w in workspaces
                          if w["monitor"] == source["monitor"] and w["id"] > 0)
    for candidate in same_monitor:
        cand_cap = workspace_caps.get(candidate, max_windows) if workspace_caps else max_windows
        if candidate > current_ws_id and counts.get(candidate, 0) < cand_cap:
            return candidate
    used = {w["id"] for w in workspaces}
    candidate = max(same_monitor) + 1
    while candidate in used:
        candidate += 1
    return candidate


def plan_move(clients, workspaces, address, cap, workspace_caps=None):
    window = next((c for c in clients if c.get("address") == address), None)
    # A group moves together; leave deliberate tab groups alone.
    if not window or not is_tiled(window) or window.get("grouped"):
        return None
    counts = tiling_counts(clients)
    source = window["workspace"]["id"]
    source_cap = workspace_caps.get(source, cap) if workspace_caps else cap
    if counts[source] <= source_cap:
        return None
    target = pick_target_ws(workspaces, counts, source, cap, workspace_caps)
    return {"address": address, "source": source, "target": target} if target else None


def read_settings():
    path = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "omarchy/shell.json"
    with path.open() as stream:
        config = json.load(stream)
    entries = config.get("bar", {}).get("layout", {})
    for section in ("left", "center", "right"):
        for entry in entries.get(section, []):
            if entry.get("id") == PLUGIN_ID:
                cap = entry.get("maxWindows", 2)
                if type(cap) is not int or not 1 <= cap <= 8:
                    cap = 2
                raw_caps = entry.get("workspaceCaps", {})
                workspace_caps = {}
                if isinstance(raw_caps, dict):
                    for k, v in raw_caps.items():
                        ws_id = None
                        if type(k) is int:
                            ws_id = k
                        elif isinstance(k, str) and k.isdigit():
                            ws_id = int(k)
                        if ws_id is not None and ws_id > 0 and type(v) is int and 1 <= v <= 8:
                            workspace_caps[ws_id] = v
                return {"enabled": entry.get("active", True) is True,
                        "cap": cap, "workspace_caps": workspace_caps,
                        "follow": entry.get("follow", True) is True}
    return {"enabled": False, "cap": 2, "workspace_caps": {}, "follow": True}


def hypr(*args):
    result = subprocess.run(["hyprctl", *args], capture_output=True,
                            text=True, timeout=3, check=True)
    return result.stdout


def move_expression(address, target, follow):
    # Only validated hexadecimal addresses and integers enter Lua code.
    address = normalize_addr(address)
    if type(target) is not int or target <= 0:
        raise ValueError("invalid target workspace")
    return ('hl.dispatch(hl.dsp.window.move({window="address:%s", '
            'workspace="%d", follow=%s}))' %
            (address, target, "true" if follow else "false"))


def get_runtime_dir():
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if runtime:
        runtime_path = Path(runtime)
        try:
            st = runtime_path.lstat()
            if runtime_path.is_symlink():
                raise RuntimeError(f"unsafe symlinked XDG_RUNTIME_DIR: {runtime_path}")
            if not stat.S_ISDIR(st.st_mode):
                raise RuntimeError(f"XDG_RUNTIME_DIR is not a directory: {runtime_path}")
            if st.st_uid != os.getuid():
                raise RuntimeError(f"XDG_RUNTIME_DIR not owned by current user: {runtime_path}")
            if st.st_mode & 0o022 != 0:
                raise RuntimeError(f"insecure permissions on XDG_RUNTIME_DIR: {runtime_path}")
            return runtime_path
        except FileNotFoundError:
            pass

    fallback = Path(f"/tmp/omarchy-simple-tile-{os.getuid()}")
    try:
        st = fallback.lstat()
        if fallback.is_symlink():
            raise RuntimeError(f"unsafe pre-existing symlinked runtime directory: {fallback}")
        if not stat.S_ISDIR(st.st_mode):
            raise RuntimeError(f"unsafe pre-existing runtime path is not a directory: {fallback}")
        if st.st_uid != os.getuid():
            raise RuntimeError(f"unsafe runtime directory ownership: {fallback}")
        if st.st_mode & 0o077 != 0:
            raise RuntimeError(f"unsafe runtime directory permissions: {fallback}")
        return fallback
    except FileNotFoundError:
        fallback.mkdir(mode=0o700, exist_ok=False)
        return fallback


@contextmanager
def runtime_lock():
    runtime_dir = get_runtime_dir()
    lock_path = runtime_dir / "omarchy-simple-tile.lock"

    try:
        st = lock_path.lstat()
        if lock_path.is_symlink():
            raise RuntimeError(f"unsafe pre-existing symlinked lock: {lock_path}")
        if not stat.S_ISREG(st.st_mode):
            raise RuntimeError(f"unsafe pre-existing lock is not a regular file: {lock_path}")
        if st.st_uid != os.getuid():
            raise RuntimeError(f"unsafe lock file ownership: {lock_path}")
    except FileNotFoundError:
        pass

    flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(str(lock_path), flags, 0o600)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            raise RuntimeError(f"opened lock file descriptor is not a regular file: {lock_path}")
        if st.st_uid != os.getuid():
            raise RuntimeError(f"opened lock file descriptor not owned by current user: {lock_path}")
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            yield
        finally:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            except OSError:
                pass
    finally:
        os.close(fd)


def handle_open(address, dry_run=False):
    # All bar instances share this lock. Re-query after acquiring it so
    # simultaneous windows and multi-monitor event delivery cannot overfill.
    with runtime_lock():
        for attempt in range(4):
            settings = read_settings()
            if not settings["enabled"]:
                return {"status": "paused"}
            clients = json.loads(hypr("clients", "-j"))
            window = next((c for c in clients if c.get("address") == address), None)
            if window and window.get("mapped"):
                break
            if attempt < 3:
                time.sleep(0.1)
        workspaces = json.loads(hypr("workspaces", "-j"))
        plan = plan_move(clients, workspaces, address, settings["cap"], settings.get("workspace_caps"))
        if plan is None:
            return {"status": "unchanged"}
        if dry_run:
            return {"status": "planned", **plan}
        output = hypr("eval", move_expression(address, plan["target"], settings["follow"]))
        # hyprctl can exit successfully while reporting a Lua error.
        after = json.loads(hypr("clients", "-j"))
        moved = next((c for c in after if c.get("address") == address), None)
        if not moved or moved.get("workspace", {}).get("id") != plan["target"]:
            raise RuntimeError("move was not confirmed: " + output.strip())
        return {"status": "moved", **plan}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--window", required=True, type=normalize_addr)
    parser.add_argument("--dry-run", action="store_true", help="report a move without dispatching it")
    args = parser.parse_args(argv)
    try:
        print(json.dumps(handle_open(args.window, args.dry_run)))
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({"status": "error", "message": str(error)}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
