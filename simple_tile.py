#!/usr/bin/env python3
"""Handle window open events and workspace layout capture/restoration.

Only newly opened windows trigger automatic overflow moves. Manually moving
windows (e.g. with Super+Shift+2) intentionally overrides the workspace window
limit, preserving full user control over window layout.
Workspaces configured in manual mode preserve their layouts and do not trigger
automatic overflow moves.
"""

from __future__ import annotations

import argparse
from collections import Counter
import configparser
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import shlex
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


def workspace_limit(ws_id, cap, workspace_caps=None, workspace_auto_presets=None,
                    default_auto_presets=None):
    limit = (workspace_caps or {}).get(ws_id, cap)
    preset = ((workspace_auto_presets or {}).get(ws_id)
              or (default_auto_presets or {}).get(str(limit)))
    return None if preset == "none" else limit


def pick_target_ws(workspaces, counts, current_ws_id, max_windows, workspace_caps=None,
                   workspace_auto_presets=None, default_auto_presets=None, workspace_modes=None):
    """Scan forward on this monitor; never reuse another monitor's ID."""
    if type(current_ws_id) is not int or current_ws_id <= 0:
        return None
    source = next((w for w in workspaces if w["id"] == current_ws_id), None)
    if source is None:
        return None
    same_monitor = sorted(w["id"] for w in workspaces
                          if w["monitor"] == source["monitor"] and w["id"] > 0)
    for candidate in same_monitor:
        if (workspace_modes or {}).get(candidate) == "manual":
            continue
        cand_cap = workspace_limit(candidate, max_windows, workspace_caps,
                                   workspace_auto_presets, default_auto_presets)
        if candidate > current_ws_id and (cand_cap is None or counts.get(candidate, 0) < cand_cap):
            return candidate
    used = {w["id"] for w in workspaces}
    used.update(ws for ws, mode in (workspace_modes or {}).items() if mode == "manual")
    candidate = max(same_monitor) + 1
    while candidate in used:
        candidate += 1
    return candidate


def plan_move(clients, workspaces, address, cap, workspace_caps=None, workspace_modes=None,
              workspace_auto_presets=None, default_auto_presets=None):
    window = next((c for c in clients if c.get("address") == address), None)
    # A group moves together; leave deliberate tab groups alone.
    if not window or not is_tiled(window) or window.get("grouped"):
        return None
    source = window["workspace"]["id"]
    if workspace_modes and workspace_modes.get(source) == "manual":
        return None
    counts = tiling_counts(clients)
    source_cap = workspace_limit(source, cap, workspace_caps,
                                 workspace_auto_presets, default_auto_presets)
    if source_cap is None or counts[source] <= source_cap:
        return None
    target = pick_target_ws(workspaces, counts, source, cap, workspace_caps,
                            workspace_auto_presets, default_auto_presets, workspace_modes)
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
                if type(cap) is not int or not 1 <= cap <= 4:
                    cap = 2
                raw_caps = entry.get("workspaceCaps", {})
                workspace_caps = {}
                if isinstance(raw_caps, dict):
                    for k, v in raw_caps.items():
                        ws_id = int(k) if type(k) is int or (isinstance(k, str) and k.isdigit()) else None
                        if ws_id is not None and ws_id > 0 and type(v) is int and 1 <= v <= 4:
                            workspace_caps[ws_id] = v
                raw_modes = entry.get("workspaceModes", {})
                workspace_modes = {}
                if isinstance(raw_modes, dict):
                    for k, v in raw_modes.items():
                        ws_id = int(k) if type(k) is int or (isinstance(k, str) and k.isdigit()) else None
                        if ws_id is not None and ws_id > 0 and v in ("auto", "manual"):
                            workspace_modes[ws_id] = v
                raw_layouts = entry.get("workspaceLayouts", {})
                workspace_layouts = {}
                if isinstance(raw_layouts, dict):
                    for k, v in raw_layouts.items():
                        ws_id = int(k) if type(k) is int or (isinstance(k, str) and k.isdigit()) else None
                        if ws_id is not None and ws_id > 0 and isinstance(v, dict):
                            workspace_layouts[ws_id] = v
                raw_auto_presets = entry.get("workspaceAutoPresets", {})
                workspace_auto_presets = {}
                if isinstance(raw_auto_presets, dict):
                    for k, v in raw_auto_presets.items():
                        ws_id = int(k) if type(k) is int or (isinstance(k, str) and k.isdigit()) else None
                        if ws_id is not None and ws_id > 0 and isinstance(v, str):
                            workspace_auto_presets[ws_id] = v
                raw_default_presets = entry.get("defaultAutoPresets", {})
                default_auto_presets = {}
                if isinstance(raw_default_presets, dict):
                    for k, v in raw_default_presets.items():
                        if str(k) in ("2", "3", "4") and isinstance(v, str):
                            default_auto_presets[str(k)] = v
                return {"enabled": entry.get("active", True) is True,
                        "cap": cap, "workspace_caps": workspace_caps,
                        "workspace_modes": workspace_modes,
                        "workspace_layouts": workspace_layouts,
                        "workspace_auto_presets": workspace_auto_presets,
                        "default_auto_presets": default_auto_presets}
    return {"enabled": False, "cap": 2, "workspace_caps": {},
            "workspace_modes": {}, "workspace_layouts": {},
            "workspace_auto_presets": {}, "default_auto_presets": {}}


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


def get_desktop_directories():
    candidates = [
        Path.home() / ".local/share/applications",
        Path("/usr/local/share/applications"),
        Path("/usr/share/applications"),
        Path.home() / ".local/share/flatpak/exports/share/applications",
        Path("/var/lib/flatpak/exports/share/applications"),
    ]
    return [d for d in candidates if d.is_dir()]


def parse_desktop_files():
    apps, seen_ids = [], set()
    for directory in get_desktop_directories():
        for path in directory.glob("*.desktop"):
            if path.name in seen_ids:
                continue
            seen_ids.add(path.name)
            values, section = {}, None
            try:
                for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
                    line = raw.strip()
                    if line.startswith("[") and line.endswith("]"):
                        section = line.strip("[]")
                    elif section == "Desktop Entry" and "=" in line:
                        k, v = line.split("=", 1)
                        values[k.strip()] = v.strip()
            except OSError:
                continue
            name = values.get("Name")
            exec_cmd = values.get("Exec")
            if not name or not exec_cmd:
                continue
            if values.get("NoDisplay", "").lower() in ("true", "1"):
                continue
            apps.append({
                "name": name,
                "exec": exec_cmd,
                "icon": values.get("Icon", ""),
                "desktop_path": str(path),
                "desktop_id": path.stem,
                "startup_class": values.get("StartupWMClass", ""),
            })
    return apps


def get_terminal_active_command(pid, terminal_cls):
    """If the window is a terminal emulator, find the foreground/active command inside it."""
    shells = {"sh", "bash", "zsh", "fish", "dash", "csh", "tcsh", "login", "init", "systemd"}
    terminal_bins = {"foot", "footclient", "alacritty", "kitty", "ghostty", "wezterm-gui", "xterm", "gnome-terminal-server"}

    def get_children(p):
        children = []
        try:
            cf = Path(f"/proc/{p}/task/{p}/children")
            if cf.exists():
                children = [int(x) for x in cf.read_text().split()]
        except Exception:
            pass
        if not children:
            try:
                for proc in Path("/proc").iterdir():
                    if proc.name.isdigit():
                        try:
                            stat = (proc / "stat").read_text()
                            ppid = int(stat.split(")")[1].split()[1])
                            if ppid == p:
                                children.append(int(proc.name))
                        except Exception:
                            pass
            except Exception:
                pass
        return children

    queue = get_children(pid)
    candidate_proc = None

    while queue:
        curr = queue.pop(0)
        try:
            exe_name = Path(os.readlink(f"/proc/{curr}/exe")).name.casefold()
        except Exception:
            try:
                exe_name = Path(f"/proc/{curr}/comm").read_text().strip().casefold()
            except Exception:
                exe_name = ""

        if exe_name and exe_name not in shells and exe_name not in terminal_bins:
            candidate_proc = (curr, exe_name)
        queue.extend(get_children(curr))

    if not candidate_proc:
        return None

    cpid, cname = candidate_proc
    try:
        raw = Path(f"/proc/{cpid}/cmdline").read_bytes()
        cmdline = [part.decode("utf-8", errors="ignore") for part in raw.split(b"\0") if part]
    except Exception:
        cmdline = [cname]

    try:
        exe_path = str(Path(os.readlink(f"/proc/{cpid}/exe")).resolve())
        if cmdline and not shutil.which(cmdline[0]) and Path(exe_path).is_file():
            cmdline[0] = exe_path
    except Exception:
        pass

    try:
        cwd = str(Path(f"/proc/{cpid}/cwd").resolve())
    except Exception:
        cwd = ""

    t_cls = terminal_cls.lower()
    t_bin = shutil.which(t_cls) or shutil.which("foot") or "foot"

    if "foot" in t_cls:
        argv = [t_bin]
        if cwd and Path(cwd).is_dir():
            argv.extend(["-D", cwd])
        argv.extend(cmdline)
    elif "alacritty" in t_cls:
        argv = [t_bin]
        if cwd and Path(cwd).is_dir():
            argv.extend(["--working-directory", cwd])
        argv.extend(["-e", *cmdline])
    elif "kitty" in t_cls:
        argv = [t_bin]
        if cwd and Path(cwd).is_dir():
            argv.extend(["--directory", cwd])
        argv.extend(cmdline)
    elif "ghostty" in t_cls:
        argv = [t_bin]
        if cwd and Path(cwd).is_dir():
            argv.extend(["--working-directory", cwd])
        argv.extend(["-e", *cmdline])
    else:
        argv = [t_bin, *cmdline]

    return {
        "name": cname.capitalize(),
        "command": cname,
        "argv": argv,
        "cwd": cwd,
        "icon": "utilities-terminal",
    }


def resolve_app_for_client(client, desktop_apps):
    cls = client.get("class", "").strip()
    icls = client.get("initialClass", "").strip()
    pid = client.get("pid", 0)

    # 0. Check if this is a terminal running a specific CLI tool (e.g. codex, nvim)
    terminal_classes = {"foot", "footclient", "alacritty", "kitty", "ghostty", "wezterm", "xterm", "gnome-terminal"}
    if pid and any(t in cls.lower() for t in terminal_classes):
        active_cmd = get_terminal_active_command(pid, cls)
        if active_cmd:
            cmd_name = active_cmd["command"]
            icon = "utilities-terminal"
            for d in desktop_apps:
                if d.get("desktop_id", "").casefold() == cmd_name or d.get("name", "").casefold() == cmd_name:
                    if d.get("icon"):
                        icon = d.get("icon")
                    break
            return {
                "name": active_cmd["name"],
                "class": cls,
                "desktop_id": cmd_name,
                "desktop_path": "",
                "icon": icon,
                "argv": active_cmd["argv"],
                "cwd": active_cmd["cwd"],
            }

    # 1. Match StartupWMClass
    for app in desktop_apps:
        sc = app.get("startup_class", "")
        if sc and (sc.casefold() == cls.casefold() or sc.casefold() == icls.casefold()):
            return app

    # 2. Match desktop_id
    for app in desktop_apps:
        did = app.get("desktop_id", "")
        if did and (did.casefold() == cls.casefold() or did.casefold() == icls.casefold()):
            return app

    # 2b. Match webapps / domain in class or Exec
    cls_lower = cls.casefold()
    for app in desktop_apps:
        did = app.get("desktop_id", "").casefold()
        name = app.get("name", "").casefold()
        exec_cmd = app.get("exec", "").casefold()
        if (did and did in cls_lower) or (name and name in cls_lower):
            return app
        if "omarchy-launch-webapp" in exec_cmd:
            url_part = exec_cmd.split()[-1].replace("https://", "").replace("http://", "").split("/")[0]
            if url_part and (url_part in cls_lower or cls_lower in url_part):
                return app

    # 3. Match /proc/<pid>/exe
    if pid:
        try:
            exe_target = Path(os.readlink(f"/proc/{pid}/exe")).name.casefold()
            for app in desktop_apps:
                did = app.get("desktop_id", "").casefold()
                if did == exe_target:
                    return app
        except OSError:
            pass

    # 4. Fallback from cmdline or class
    cmdline = []
    if pid:
        try:
            raw = Path(f"/proc/{pid}/cmdline").read_bytes()
            cmdline = [part.decode("utf-8", errors="ignore") for part in raw.split(b"\0") if part]
            if len(cmdline) == 1 and " " in cmdline[0]:
                import shlex
                cmdline = shlex.split(cmdline[0])
        except OSError:
            pass

    return {
        "name": cls.capitalize() if cls else "Application",
        "class": cls,
        "desktop_id": cls.casefold(),
        "desktop_path": "",
        "icon": cls.casefold() if cls else "application-x-executable",
        "argv": cmdline,
    }


def detect_layout_preset(windows):
    tiled = [w for w in windows if not w.get("floating")]
    count = len(tiled)
    if count <= 1:
        return "none"
    if count == 2:
        dx = abs(tiled[0].get("at", [0, 0])[0] - tiled[1].get("at", [0, 0])[0])
        dy = abs(tiled[0].get("at", [0, 0])[1] - tiled[1].get("at", [0, 0])[1])
        return "side-by-side" if dx >= dy else "stacked"
    if count == 3:
        heights = [w.get("size", [0, 0])[1] for w in tiled]
        max_h = max(heights)
        min_h = min(heights)
        if max_h >= min_h * 1.3:
            master = max(tiled, key=lambda w: w.get("size", [0, 0])[1])
            slaves = [w for w in tiled if w is not master]
            slaves_x = [w.get("at", [0, 0])[0] for w in slaves]
            if master.get("at", [0, 0])[0] < min(slaves_x):
                return "master-left"
            else:
                return "master-right"
        return "columns"
    if count == 4:
        xs = sorted(w.get("at", [0, 0])[0] for w in tiled)
        if all(xs[i+1] - xs[i] > 80 for i in range(3)):
            return "columns"
        return "grid"
    return "none"


def capture_workspace(ws_id):
    if type(ws_id) is not int or ws_id <= 0:
        raise ValueError("invalid workspace id")
    clients = json.loads(hypr("clients", "-j"))
    ws_clients = [c for c in clients if c.get("workspace", {}).get("id") == ws_id and c.get("mapped", False)]

    desktop_apps = parse_desktop_files()
    apps = []
    seen_app_ids = set()
    windows = []

    for c in ws_clients:
        win_info = {
            "address": normalize_addr(c.get("address")),
            "class": c.get("class", ""),
            "title": c.get("title", ""),
            "at": c.get("at", [0, 0]),
            "size": c.get("size", [0, 0]),
            "floating": bool(c.get("floating", False)),
        }
        windows.append(win_info)

        app = resolve_app_for_client(c, desktop_apps)
        if app:
            win_info["app"] = dict(app)
        win_info["initialClass"] = c.get("initialClass", "")
        if app:
            app_key = app.get("desktop_id") or app.get("class") or app.get("name")
            if app_key and app_key not in seen_app_ids:
                seen_app_ids.add(app_key)
                apps.append({
                    "name": app.get("name", ""),
                    "class": app.get("class", c.get("class", "")),
                    "icon": app.get("icon", "application-x-executable"),
                    "desktop_id": app.get("desktop_id", ""),
                    "desktop_path": app.get("desktop_path", ""),
                    "argv": app.get("argv", []),
                })

    session = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if session:
        try:
            marker = get_runtime_dir() / ("simple-tile-autostart-" + hashlib.sha256(session.encode()).hexdigest())
            if marker.exists():
                marker.unlink()
        except Exception:
            pass

    detected_preset = detect_layout_preset(windows)
    settings = read_settings()
    configured_preset = settings.get("workspace_auto_presets", {}).get(ws_id)
    preset = configured_preset or detected_preset

    return {
        "status": "ok",
        "workspace": ws_id,
        "count": len(windows),
        "preset": preset,
        "windows": windows,
        "apps": apps
    }


def is_app_available(app):
    """Check if an app can be executed or located on the system."""
    if "argv" in app and app["argv"]:
        argv = app["argv"]
        if len(argv) == 1 and " " in argv[0]:
            import shlex
            try:
                argv = shlex.split(argv[0])
                app["argv"] = argv
            except Exception:
                pass
        cmd = argv[0]
        if shutil.which(cmd):
            return True, "ok"
        path = Path(cmd)
        if path.is_file() and os.access(path, os.X_OK):
            return True, "ok"
        return False, "command_not_found"

    desktop_path = app.get("desktop_path", "")
    if desktop_path:
        if Path(desktop_path).is_file():
            return True, "ok"
        desktop_id = app.get("desktop_id") or Path(desktop_path).stem
        for directory in get_desktop_directories():
            candidate = directory / f"{desktop_id}.desktop"
            if candidate.is_file():
                app["desktop_path"] = str(candidate)
                return True, "ok"
        return False, "desktop_file_not_found"

    desktop_id = app.get("desktop_id", "")
    if desktop_id:
        for directory in get_desktop_directories():
            candidate = directory / f"{desktop_id}.desktop"
            if candidate.is_file():
                app["desktop_path"] = str(candidate)
                return True, "ok"

    cls = app.get("class", "").lower()
    if cls:
        cmd = shutil.which(cls)
        if cmd:
            app["argv"] = [cmd]
            return True, "ok"

    # If neither desktop_path nor argv was specified, allow launch_app to attempt
    return True, "ok"


def send_notification(title, body, urgency="normal"):
    """Send a desktop notification via notify-send if available."""
    if shutil.which("notify-send"):
        try:
            subprocess.Popen(
                ["notify-send", "-a", "Simple Tile", "-u", urgency, title, body],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception:
            pass


def find_next_free_workspace(preferred_start=1):
    """Find the next workspace number with no open windows."""
    try:
        live = json.loads(hypr("clients", "-j"))
        occupied = {
            c.get("workspace", {}).get("id")
            for c in live
            if c.get("mapped") and not c.get("hidden")
        }
    except Exception:
        occupied = set()

    for w in range(preferred_start, 11):
        if w not in occupied and w > 0:
            return w
    for w in range(1, preferred_start):
        if w not in occupied and w > 0:
            return w
    return max(occupied | {0}) + 1


def _clean_env():
    env = os.environ.copy()
    if "LD_PRELOAD" in env:
        parts = [p for p in env["LD_PRELOAD"].split(":") if p and "libgtk4-layer-shell" not in p]
        if parts:
            env["LD_PRELOAD"] = ":".join(parts)
        else:
            del env["LD_PRELOAD"]
    return env


def app_for_restore(app, saved):
    """Request a real browser window for each missing normal Chrome slot."""
    browser_classes = {"google-chrome", "google-chrome-stable", "chromium", "chromium-browser"}
    classes = {str(saved.get(k, "")).casefold() for k in ("class", "initialClass")}
    if not classes & browser_classes:
        return app  # Chrome web apps keep their own desktop launcher.
    argv = list(app.get("argv") or [])
    try:
        if argv and len(argv) == 1 and " " in argv[0]:
            argv = shlex.split(argv[0])
        if not argv:
            # Read the installed launcher, never execute a saved raw Exec string.
            desktop = configparser.ConfigParser(interpolation=None, strict=False)
            desktop.read(app.get("desktop_path") or "", encoding="utf-8")
            argv = shlex.split(desktop.get("Desktop Entry", "Exec"))
            argv = [arg for arg in argv if arg not in ("%U", "%u", "%F", "%f")]
            if any("%" in arg for arg in argv):
                return app
    except (OSError, ValueError, configparser.Error):
        return app
    if not argv or any(arg.startswith(("--app=", "--app-id=")) for arg in argv):
        return app
    if "--new-window" not in argv:
        argv.insert(1, "--new-window")
    return dict(app, argv=argv)


def launch_app(app):
    """Launch an application following approved security guidelines.

    1. Direct argv for standalone binaries (never through a shell).
    2. uwsm-app for desktop files (in app-graphical.slice).
    3. GioUnix.DesktopAppInfo fallback for desktop files.
    Never executes arbitrary shell strings.
    """
    if "argv" in app and app["argv"]:
        argv = app["argv"]
        if len(argv) == 1 and " " in argv[0]:
            import shlex
            try:
                argv = shlex.split(argv[0])
                app["argv"] = argv
            except Exception:
                pass
        try:
            subprocess.Popen(
                argv,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
                env=_clean_env(),
            )
            return True
        except OSError:
            return False

    desktop_path = app.get("desktop_path", "")

    # 1. Primary: uwsm-app
    if desktop_path and shutil.which("uwsm-app"):
        try:
            subprocess.Popen(
                ["uwsm-app", "--", desktop_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
                env=_clean_env(),
            )
            return True
        except OSError:
            pass

    # 2. Native Gio fallback
    if desktop_path:
        try:
            from gi.repository import GioUnix
            info = GioUnix.DesktopAppInfo.new_from_filename(desktop_path)
            if info:
                return bool(info.launch_uris([], None))
        except Exception:
            pass

    return False


def matches_window(saved, client):
    classes = {str(saved.get(k, "")).casefold() for k in ("class", "initialClass")}
    classes.discard("")
    return bool(classes & {str(client.get(k, "")).casefold()
                           for k in ("class", "initialClass")})


def wait_for_window(saved, before, timeout=20):
    deadline = time.monotonic() + timeout
    while True:
        clients = json.loads(hypr("clients", "-j"))
        candidates = [c for c in clients if c.get("mapped") and not c.get("hidden")
                      and c.get("address") not in before and matches_window(saved, c)]
        if candidates:
            return max(candidates, key=lambda c: c.get("title") == saved.get("title"))
        if time.monotonic() >= deadline:
            return None
        time.sleep(0.1)


def wait_for_closed_windows(addresses, timeout=8):
    """A close dispatch is a request; apps may delay or show a save dialog."""
    deadline = time.monotonic() + timeout
    while True:
        clients = json.loads(hypr("clients", "-j"))
        remaining = [c for c in clients if c.get("mapped") and c.get("address") in addresses]
        if not remaining or time.monotonic() >= deadline:
            return clients, remaining
        time.sleep(0.1)


def layout_tree(windows):
    """Recover a slicing tree from saved rectangles, independent of app order."""
    if not windows or any(len(w.get("at", [])) != 2 or len(w.get("size", [])) != 2
                          or any(type(v) not in (int, float) for v in w["at"] + w["size"])
                          or min(w["size"]) <= 0 for w in windows):
        raise ValueError("Invalid saved window geometry; save the layout again")
    if len(windows) == 1:
        return windows[0]
    for axis in (0, 1):
        ordered = sorted(windows, key=lambda w: w["at"][axis])
        for i in range(1, len(ordered)):
            left, right = ordered[:i], ordered[i:]
            edge = max(w["at"][axis] + w["size"][axis] for w in left)
            start = min(w["at"][axis] for w in right)
            if edge > start:
                continue
            low = min(w["at"][axis] for w in ordered)
            high = max(w["at"][axis] + w["size"][axis] for w in ordered)
            return {"axis": axis, "ratio": 2 * ((edge + start) / 2 - low) / (high - low),
                    "left": layout_tree(left), "right": layout_tree(right)}
    raise ValueError("Saved tiled windows overlap; save an ungrouped tiled layout first")


def align_tiled_windows(ws_id, pairs):
    tiled_pairs = [(saved, client) for saved, client in pairs if not saved.get("floating")]
    if len(tiled_pairs) < 2:
        return
    try:
        live_clients = [c for c in json.loads(hypr("clients", "-j"))
                        if c.get("workspace", {}).get("id") == ws_id and is_tiled(c)]
    except Exception:
        return
    if len(live_clients) < 2:
        return

    # Map each saved window to the live slot closest to saved["at"]
    unassigned_slots = list(live_clients)
    desired_slot_for_client = {}

    for saved, client in tiled_pairs:
        s_at = saved.get("at", [0, 0])
        if not unassigned_slots:
            break
        closest = min(unassigned_slots, key=lambda c: (c.get("at", [0, 0])[0] - s_at[0])**2 + (c.get("at", [0, 0])[1] - s_at[1])**2)
        desired_slot_for_client[normalize_addr(client["address"])] = normalize_addr(closest["address"])
        unassigned_slots.remove(closest)

    current_occupant = {normalize_addr(c["address"]): normalize_addr(c["address"]) for c in live_clients}
    client_to_slot = {normalize_addr(c["address"]): normalize_addr(c["address"]) for c in live_clients}

    for client_addr, target_slot in desired_slot_for_client.items():
        curr_slot = client_to_slot.get(client_addr)
        if curr_slot and curr_slot != target_slot:
            other_client = current_occupant.get(target_slot)
            if other_client and other_client != client_addr:
                lua_expr = 'hl.dispatch(hl.dsp.window.swap({window="address:%s", with="address:%s"}))' % (client_addr, other_client)
                try:
                    hypr("eval", lua_expr)
                except Exception:
                    pass
                current_occupant[target_slot] = client_addr
                current_occupant[curr_slot] = other_client
                client_to_slot[client_addr] = target_slot
                client_to_slot[other_client] = curr_slot


def restore_geometry(ws_id, pairs):
    tiled = [dict(saved, address=client["address"]) for saved, client in pairs
             if not saved.get("floating")]
    if any(c.get("grouped") or c.get("fullscreen") for _, c in pairs):
        raise ValueError("Grouped or fullscreen windows must be ungrouped/unfullscreened before restoring")
    # Validate the complete tree before changing any window state.
    tree = layout_tree(tiled) if tiled else None
    live = json.loads(hypr("clients", "-j"))
    addresses = {c["address"] for _, c in pairs}
    if any(is_tiled(c) and c["workspace"]["id"] == ws_id
           and c["address"] not in addresses for c in live):
        raise ValueError("Workspace has extra tiled windows; move them away before restoring the saved layout")

    def dispatch(expr):
        result = hypr("eval", "hl.dispatch(hl.dsp." + expr + ")")
        if "error" in result.lower():
            raise RuntimeError(result.strip())

    def target(w):
        return 'window="address:%s"' % normalize_addr(w["address"])

    def first(node):
        return first(node["left"]) if "axis" in node else node

    def build(node):
        if "axis" not in node:
            return
        left, right = first(node["left"]), first(node["right"])
        dispatch('focus({' + target(left) + '})')
        dispatch('layout("preselect %s")' % ("r" if node["axis"] == 0 else "d"))
        dispatch('window.float({' + target(right) + ', action="off"})')
        dispatch('focus({' + target(left) + '})')
        dispatch('layout("splitratio %.8f exact")' % node["ratio"])
        build(node["left"])
        build(node["right"])

    hypr("eval", 'hl.dispatch(hl.dsp.focus({workspace=%d}))' % ws_id)
    # Use native dwindle tiles, including for rectangles originally made in master.
    if tiled:
        hypr("eval", 'hl.workspace_rule({workspace="%d", layout="dwindle"})' % ws_id)
    try:
        for saved, client in pairs:
            dispatch('window.float({' + target(client) + ', action="on"})')
        if tree:
            dispatch('window.float({' + target(first(tree)) + ', action="off"})')
            build(tree)
        for saved, client in pairs:
            if saved.get("floating"):
                dispatch('window.resize({' + target(client) + ', x=%d, y=%d, relative=false})' % tuple(saved["size"]))
                dispatch('window.move({' + target(client) + ', x=%d, y=%d, relative=false})' % tuple(saved["at"]))
    finally:
        # Never leave originally tiled windows floating after a failed rebuild.
        for window in tiled:
            dispatch('window.float({' + target(window) + ', action="off"})')
        if tiled:
            dispatch('layout("preselect none")')

    align_tiled_windows(ws_id, pairs)

    actual = {c["address"]: c for c in json.loads(hypr("clients", "-j"))}
    for saved, client in pairs:
        current = actual.get(client["address"])
        if (not current or current.get("workspace", {}).get("id") != ws_id
                or bool(current.get("floating")) != bool(saved.get("floating"))):
            raise RuntimeError("Window placement could not be verified")
    # Check relative slot order, rather than reporting success after IPC alone.
    for left in tiled:
        for right in tiled:
            if left is right:
                continue
            for axis in (0, 1):
                if left["at"][axis] + left["size"][axis] <= right["at"][axis]:
                    a, b = actual[left["address"]], actual[right["address"]]
                    if a["at"][axis] + a["size"][axis] > b["at"][axis] + 4:
                        raise RuntimeError("Saved tile positions could not be restored")


def restore_workspace(ws_id, dry_run=False, conflict_action="ask"):
    with runtime_lock():
        return _restore_workspace(ws_id, dry_run, conflict_action)


def _restore_workspace(ws_id, dry_run=False, conflict_action="ask"):
    if type(ws_id) is not int or ws_id <= 0:
        raise ValueError("invalid workspace id")
    if conflict_action not in ("ask", "move", "close", "keep"):
        raise ValueError("invalid conflict action: %s" % conflict_action)
    layouts = read_settings().get("workspace_layouts", {})
    layout = layouts.get(ws_id)
    if not layout:
        return {"status": "no_layout", "workspace": ws_id}
    apps = layout.get("apps", [])
    windows = layout.get("windows", [])
    if "apps" in layout and layout.get("saveApps") is not False:
        # Older remove buttons only edited apps. Do not resurrect their stale slots.
        windows = [w for w in windows if any(matches_window(w, app) for app in apps)]
    slots = windows or apps  # Legacy app-only snapshots remain usable.
    if not slots:
        return {"status": "no_apps", "workspace": ws_id}
    clients = json.loads(hypr("clients", "-j"))
    original_ws = json.loads(hypr("activeworkspace", "-j")).get("id")

    current_ws_clients = [c for c in clients if c.get("mapped") and not c.get("hidden")
                          and c.get("workspace", {}).get("id") == ws_id]

    matched_on_ws = set()
    for saved in slots:
        candidates = [c for c in current_ws_clients
                      if c.get("address") not in matched_on_ws and matches_window(saved, c)]
        if candidates:
            def candidate_score(c):
                score = 0
                if c.get("title") == saved.get("title"):
                    score += 1000
                elif saved.get("title") and saved.get("title") in c.get("title", ""):
                    score += 500
                c_at = c.get("at", [0, 0])
                s_at = saved.get("at", [0, 0])
                dist = (c_at[0] - s_at[0]) ** 2 + (c_at[1] - s_at[1]) ** 2
                score -= dist / 10000.0
                return score
            best = max(candidates, key=candidate_score)
            matched_on_ws.add(best["address"])

    extra_on_ws = [c for c in current_ws_clients if c["address"] not in matched_on_ws]

    if extra_on_ws and conflict_action == "ask":
        return {
            "status": "conflict",
            "workspace": ws_id,
            "conflict_count": len(extra_on_ws),
            "next_free_workspace": find_next_free_workspace(ws_id + 1),
            "conflicts": [
                {
                    "address": c["address"],
                    "title": c.get("title", ""),
                    "class": c.get("class", ""),
                    "initialClass": c.get("initialClass", ""),
                }
                for c in extra_on_ws
            ],
        }

    used, pairs = set(), []
    launched, already_running, failed = [], [], []
    focus_changed = False
    try:
        if extra_on_ws and not dry_run:
            if conflict_action == "move":
                next_free = find_next_free_workspace(ws_id + 1)
                for c in extra_on_ws:
                    hypr("eval", move_expression(c["address"], next_free, False))
                names = [c.get("class") or c.get("initialClass") or "Window" for c in extra_on_ws]
                send_notification(
                    "Simple Tile",
                    "Moved %d window(s) (%s) from Workspace %d to Workspace %d" %
                    (len(extra_on_ws), ", ".join(names), ws_id, next_free)
                )
                clients = json.loads(hypr("clients", "-j"))
            elif conflict_action == "close":
                # Focus the target before closing so app confirmation dialogs
                # are visible. Never rebuild a layout around windows still closing.
                focus_changed = True
                hypr("eval", 'hl.dispatch(hl.dsp.focus({workspace=%d}))' % ws_id)
                closing = {normalize_addr(c["address"]) for c in extra_on_ws}
                for addr in sorted(closing):
                    output = hypr("eval", 'hl.dispatch(hl.dsp.window.close({window="address:%s"}))' % addr)
                    if "error" in output.lower():
                        raise RuntimeError("Could not close conflicting window: " + output.strip())
                clients, remaining = wait_for_closed_windows(closing)
                if remaining:
                    return {"status": "error", "workspace": ws_id,
                            "launched": [], "already_running": [], "geometry_restored": False,
                            "failed": [{"name": c.get("class") or c.get("initialClass") or "Window",
                                        "reason": "close_timeout"} for c in remaining]}
            elif conflict_action == "keep":
                for c in extra_on_ws:
                    if not c.get("floating"):
                        addr = normalize_addr(c["address"])
                        hypr("eval", 'hl.dispatch(hl.dsp.window.float({window="address:%s", action="on"}))' % addr)
                clients = json.loads(hypr("clients", "-j"))

        for saved in slots:
            app = saved.get("app") or next((a for a in apps if matches_window(saved, a)), saved)
            name = app.get("name") or saved.get("class") or "Application"
            candidates = [c for c in clients if c.get("mapped") and not c.get("hidden")
                          and c.get("address") not in used and matches_window(saved, c)
                          and c.get("workspace", {}).get("id") == ws_id]
            if not candidates:
                # Reuse a uniquely identifiable app on the wrong workspace, but
                # do not steal windows assigned to another saved workspace.
                elsewhere = [c for c in clients if c.get("mapped") and not c.get("hidden")
                             and c.get("address") not in used and matches_window(saved, c)
                             and not any(matches_window(slot, c) for slot in
                                 (layouts.get(c.get("workspace", {}).get("id"), {}).get("windows")
                                  or layouts.get(c.get("workspace", {}).get("id"), {}).get("apps", [])))]
                if len(elsewhere) == 1:
                    candidates = elsewhere
            def candidate_score(c):
                score = 0
                if c.get("title") == saved.get("title"):
                    score += 1000
                elif saved.get("title") and saved.get("title") in c.get("title", ""):
                    score += 500
                c_at = c.get("at", [0, 0])
                s_at = saved.get("at", [0, 0])
                dist = (c_at[0] - s_at[0]) ** 2 + (c_at[1] - s_at[1]) ** 2
                score -= dist / 10000.0
                return score

            client = max(candidates, key=candidate_score) if candidates else None
            if client:
                already_running.append(name)
            else:
                if layout.get("saveApps") is False:
                    failed.append({"name": name, "reason": "app_launching_disabled"})
                    continue
                available, reason = is_app_available(app)
                if not available:
                    failed.append({"name": name, "reason": reason})
                    continue
                if dry_run:
                    launched.append(name)
                    continue
                before = {c.get("address") for c in json.loads(hypr("clients", "-j"))}
                focus_changed = True
                hypr("eval", 'hl.dispatch(hl.dsp.focus({workspace=%d}))' % ws_id)
                if not launch_app(app_for_restore(app, saved)):
                    failed.append({"name": name, "reason": "launch_failed"})
                    continue
                client = wait_for_window(saved, before)
                if not client:
                    failed.append({"name": name, "reason": "window_timeout"})
                    continue
                launched.append(name)
            used.add(client.get("address"))
            if not dry_run:
                address = normalize_addr(client["address"])
                if client.get("workspace", {}).get("id") != ws_id:
                    hypr("eval", move_expression(address, ws_id, False))
                clients = json.loads(hypr("clients", "-j"))
                client = next((c for c in clients if c.get("address") == address), None)
                if client is None or client.get("workspace", {}).get("id") != ws_id:
                    failed.append({"name": name, "reason": "workspace_move_failed"})
                    continue
                pairs.append((saved, client))
        if windows and not dry_run and not failed:
            preset = layout.get("preset") or detect_layout_preset(windows)
            if preset and preset != "none":
                try:
                    apply_layout_preset(ws_id, preset)
                except Exception:
                    pass
            try:
                restore_geometry(ws_id, pairs)
            except (ValueError, RuntimeError, subprocess.SubprocessError) as error:
                failed.append({"name": "Layout", "reason": str(error)})
    finally:
        if original_ws and not dry_run and (focus_changed or pairs):
            hypr("eval", 'hl.dispatch(hl.dsp.focus({workspace=%d}))' % original_ws)
    return {"status": ("partial" if launched or already_running else "error") if failed else "ok",
            "workspace": ws_id, "launched": launched, "already_running": already_running,
            "geometry_restored": bool(windows and not dry_run and not failed), "failed": failed}


def autostart_all(dry_run=False):
    # A bar exists on each monitor and is recreated on shell reloads.
    # Serialize the entire batch and mark it by compositor session, not process.
    if dry_run:
        return _autostart_all(True)
    with runtime_lock():
        session = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        if not session:
            raise RuntimeError("Hyprland session is not ready")
        marker = get_runtime_dir() / ("simple-tile-autostart-" + hashlib.sha256(session.encode()).hexdigest())
        if marker.exists():
            return {"status": "already_started"}
        hypr("clients", "-j")  # Do not consume the session on an IPC readiness failure.
        result = _autostart_all(False)
        if result["workspaces"] and result.get("failed_count", 0) == 0:
            marker.write_text(json.dumps(result))
        return result


def _autostart_all(dry_run):
    started = []
    for ws_id, layout in sorted(read_settings().get("workspace_layouts", {}).items()):
        if layout.get("autostart") is True:
            # The batch already owns the runtime lock.
            restore = restore_workspace if dry_run else _restore_workspace
            kwargs = {"dry_run": dry_run}
            if not dry_run:
                kwargs["conflict_action"] = "move"
            started.append({"workspace": ws_id, "result": restore(ws_id, **kwargs)})
    failures = sum(len(w["result"].get("failed", [])) for w in started)
    return {"status": "partial" if failures else "ok", "workspaces": started, "failed_count": failures}


def apply_layout_preset(ws_id, preset, dry_run=False):
    if type(ws_id) is not int or ws_id <= 0:
        raise ValueError("invalid workspace id")
    preset = str(preset).lower()
    all_valid = {"side-by-side", "stacked", "master-left", "master-right", "columns", "grid", "none"}
    if preset not in all_valid:
        raise ValueError(f"invalid preset: {preset}")

    clients = json.loads(hypr("clients", "-j"))
    ws_clients = [c for c in clients if c.get("workspace", {}).get("id") == ws_id and is_tiled(c)]

    actions = []

    try:
        settings = read_settings()
        ws_cap = settings.get("workspace_caps", {}).get(ws_id, settings.get("cap", 2))
    except Exception:
        ws_cap = 2

    # 1. Configure workspace rule for this workspace
    if preset == "none":
        rule_lua = f'hl.workspace_rule({{ workspace = "{ws_id}", layout = "dwindle" }})'
    elif preset == "columns":
        # 4 or more windows (or cap=4 with <2 windows) need dwindle to arrange 4 side-by-side columns.
        # 3 windows use master layout with orientationcenter.
        if len(ws_clients) >= 4 or (len(ws_clients) < 2 and ws_cap == 4):
            rule_lua = f'hl.workspace_rule({{ workspace = "{ws_id}", layout = "dwindle" }})'
        else:
            rule_lua = f'hl.workspace_rule({{ workspace = "{ws_id}", layout = "master", layout_opts = {{ orientation = "center" }} }})'
    elif preset == "master-left":
        rule_lua = f'hl.workspace_rule({{ workspace = "{ws_id}", layout = "master", layout_opts = {{ orientation = "left" }} }})'
    elif preset == "master-right":
        rule_lua = f'hl.workspace_rule({{ workspace = "{ws_id}", layout = "master", layout_opts = {{ orientation = "right" }} }})'
    else:  # side-by-side, stacked, grid
        rule_lua = f'hl.workspace_rule({{ workspace = "{ws_id}", layout = "dwindle" }})'
    actions.append(("eval", rule_lua))

    # 2. Live adjustments when windows exist on this workspace
    if ws_clients and preset != "none":
        try:
            active_info = json.loads(hypr("activeworkspace", "-j"))
            original_ws = active_info.get("id")
        except Exception:
            original_ws = None

        need_focus_switch = original_ws is not None and original_ws != ws_id
        if need_focus_switch:
            actions.append(("eval", f'hl.dispatch(hl.dsp.focus({{ workspace = {ws_id} }}))'))

        if len(ws_clients) == 2:
            if preset in ("side-by-side", "stacked", "columns"):
                actions.append(("eval", f'hl.workspace_rule({{ workspace = "{ws_id}", layout = "dwindle" }})'))
                c1, c2 = ws_clients[0], ws_clients[1]
                dx = abs(c1.get("at", [0, 0])[0] - c2.get("at", [0, 0])[0])
                dy = abs(c1.get("at", [0, 0])[1] - c2.get("at", [0, 0])[1])
                is_side_by_side = dx > dy
                is_stacked = dy > dx

                if preset in ("side-by-side", "columns") and not is_side_by_side:
                    actions.append(("eval", 'hl.dispatch(hl.dsp.layout("togglesplit"))'))
                elif preset == "stacked" and not is_stacked:
                    actions.append(("eval", 'hl.dispatch(hl.dsp.layout("togglesplit"))'))
            elif preset == "master-left":
                actions.append(("eval", 'for _ = 1, 3 do pcall(function() hl.dispatch(hl.dsp.layout("removemaster")) end) end'))
                actions.append(("eval", 'hl.dispatch(hl.dsp.layout("orientationleft"))'))
            elif preset == "master-right":
                actions.append(("eval", 'for _ = 1, 3 do pcall(function() hl.dispatch(hl.dsp.layout("removemaster")) end) end'))
                actions.append(("eval", 'hl.dispatch(hl.dsp.layout("orientationright"))'))
        elif len(ws_clients) == 3:
            if preset == "columns":
                # Master in center with 1 master gives 3 side-by-side columns: Left | Center | Right
                actions.append(("eval", f'hl.workspace_rule({{ workspace = "{ws_id}", layout = "master", layout_opts = {{ orientation = "center" }} }})'))
                actions.append(("eval", 'for _ = 1, 4 do pcall(function() hl.dispatch(hl.dsp.layout("removemaster")) end) end'))
                actions.append(("eval", 'hl.dispatch(hl.dsp.layout("orientationcenter"))'))
            elif preset == "master-left":
                actions.append(("eval", 'for _ = 1, 4 do pcall(function() hl.dispatch(hl.dsp.layout("removemaster")) end) end'))
                actions.append(("eval", 'hl.dispatch(hl.dsp.layout("orientationleft"))'))
            elif preset == "master-right":
                actions.append(("eval", 'for _ = 1, 4 do pcall(function() hl.dispatch(hl.dsp.layout("removemaster")) end) end'))
                actions.append(("eval", 'hl.dispatch(hl.dsp.layout("orientationright"))'))
            elif preset == "grid":
                actions.append(("eval", f'hl.workspace_rule({{ workspace = "{ws_id}", layout = "dwindle" }})'))
        elif len(ws_clients) >= 4:
            if preset == "columns":
                # Dwindle layout with all horizontal splits produces 4 side-by-side columns
                actions.append(("eval", f'hl.workspace_rule({{ workspace = "{ws_id}", layout = "dwindle" }})'))
                stacked = [c for c in ws_clients if c.get("size", [0, 0])[1] < 900]
                if stacked:
                    seen_x = set()
                    for s in stacked:
                        x = s.get("at", [0, 0])[0]
                        if not any(abs(x - prev_x) < 30 for prev_x in seen_x):
                            seen_x.add(x)
                            addr = normalize_addr(s.get("address")) if s.get("address") else ""
                            if addr:
                                actions.append(("eval", f'''(function()
                                    local w = hl.get_window("address:{addr}")
                                    if w then
                                        hl.dispatch(hl.dsp.focus({{ window = w }}))
                                        pcall(function() hl.dispatch(hl.dsp.layout("togglesplit")) end)
                                    end
                                end)()'''))
                else:
                    actions.append(("eval", 'pcall(function() hl.dispatch(hl.dsp.layout("togglesplit")) end)'))
            elif preset == "master-left":
                actions.append(("eval", 'for _ = 1, 4 do pcall(function() hl.dispatch(hl.dsp.layout("removemaster")) end) end'))
                actions.append(("eval", 'hl.dispatch(hl.dsp.layout("orientationleft"))'))
            elif preset == "master-right":
                actions.append(("eval", 'for _ = 1, 4 do pcall(function() hl.dispatch(hl.dsp.layout("removemaster")) end) end'))
                actions.append(("eval", 'hl.dispatch(hl.dsp.layout("orientationright"))'))
            elif preset == "grid":
                actions.append(("eval", f'hl.workspace_rule({{ workspace = "{ws_id}", layout = "dwindle" }})'))

        if need_focus_switch:
            actions.append(("eval", f'hl.dispatch(hl.dsp.focus({{ workspace = {original_ws} }}))'))

    if not dry_run:
        for cmd, code in actions:
            try:
                hypr(cmd, code)
            except Exception:
                pass

        if len(ws_clients) >= 4 and preset == "columns":
            try:
                for _ in range(4):
                    time.sleep(0.08)
                    after_clients = json.loads(hypr("clients", "-j"))
                    still_stacked = [c for c in after_clients if c.get("workspace", {}).get("id") == ws_id and is_tiled(c) and c.get("size", [0, 0])[1] < 900]
                    if not still_stacked:
                        break
                    target = still_stacked[0]
                    addr = normalize_addr(target.get("address")) if target.get("address") else ""
                    if addr:
                        hypr("eval", f'''(function()
                            local w = hl.get_window("address:{addr}")
                            if w then
                                hl.dispatch(hl.dsp.focus({{ window = w }}))
                                pcall(function() hl.dispatch(hl.dsp.layout("togglesplit")) end)
                            end
                        end)()''')
                if need_focus_switch and original_ws is not None:
                    hypr("eval", f'hl.dispatch(hl.dsp.focus({{ workspace = {original_ws} }}))')
            except Exception:
                pass

    return {
        "status": "ok",
        "workspace": ws_id,
        "preset": preset,
        "actions": len(actions)
    }


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

        source = None
        if window:
            source = window.get("workspace", {}).get("id")
            if settings.get("workspace_modes", {}).get(source) == "manual":
                return {"status": "manual", "workspace": source}

        workspaces = json.loads(hypr("workspaces", "-j"))
        plan = plan_move(clients, workspaces, address, settings["cap"],
                         settings.get("workspace_caps"), settings.get("workspace_modes"),
                         settings.get("workspace_auto_presets"), settings.get("default_auto_presets"))
        if plan is None:
            # Window stays on source workspace; apply auto preset if configured
            if source and settings.get("workspace_modes", {}).get(source) != "manual":
                cap = settings.get("workspace_caps", {}).get(source, settings.get("cap", 2))
                preset = (settings.get("workspace_auto_presets", {}).get(source)
                          or settings.get("default_auto_presets", {}).get(str(cap)))
                if preset and preset != "none":
                    try:
                        apply_layout_preset(source, preset, dry_run=dry_run)
                    except Exception:
                        pass
            return {"status": "unchanged"}
        if dry_run:
            return {"status": "planned", **plan}
        output = hypr("eval", move_expression(address, plan["target"], True))
        # hyprctl can exit successfully while reporting a Lua error.
        after = json.loads(hypr("clients", "-j"))
        moved = next((c for c in after if c.get("address") == address), None)
        if not moved or moved.get("workspace", {}).get("id") != plan["target"]:
            raise RuntimeError("move was not confirmed: " + output.strip())

        # Apply auto preset to target workspace if configured
        target_ws = plan["target"]
        if target_ws and settings.get("workspace_modes", {}).get(target_ws) != "manual":
            cap = settings.get("workspace_caps", {}).get(target_ws, settings.get("cap", 2))
            preset = (settings.get("workspace_auto_presets", {}).get(target_ws)
                      or settings.get("default_auto_presets", {}).get(str(cap)))
            if preset and preset != "none":
                try:
                    apply_layout_preset(target_ws, preset, dry_run=dry_run)
                except Exception:
                    pass

        return {"status": "moved", **plan}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--window", required=False, type=normalize_addr, help="handle window open event")
    parser.add_argument("--dry-run", action="store_true", help="report actions without dispatching")
    parser.add_argument("--capture-workspace", type=int, metavar="WS_ID", help="capture windows and apps for workspace")
    parser.add_argument("--restore-workspace", type=int, metavar="WS_ID", help="launch missing saved apps for workspace")
    parser.add_argument("--conflict-action", choices=["ask", "move", "close", "keep"], default="ask",
                        help="action to take if extra windows are found on workspace when restoring")
    parser.add_argument("--autostart", action="store_true", help="launch saved apps for all autostart workspaces")
    parser.add_argument("--apply-preset", nargs=2, metavar=("WS_ID", "PRESET"), help="apply layout preset to workspace")
    parser.add_argument("--remove-preset", type=int, metavar="WS_ID", help="remove layout preset from workspace")
    args = parser.parse_args(argv)

    try:
        if args.capture_workspace is not None:
            print(json.dumps(capture_workspace(args.capture_workspace)))
            return 0
        if args.restore_workspace is not None:
            print(json.dumps(restore_workspace(args.restore_workspace, args.dry_run, args.conflict_action)))
            return 0
        if args.autostart:
            print(json.dumps(autostart_all(args.dry_run)))
            return 0
        if args.remove_preset is not None:
            print(json.dumps(apply_layout_preset(args.remove_preset, "none", args.dry_run)))
            return 0
        if args.apply_preset:
            ws_id = int(args.apply_preset[0])
            preset = args.apply_preset[1]
            print(json.dumps(apply_layout_preset(ws_id, preset, args.dry_run)))
            return 0
        if args.window:
            print(json.dumps(handle_open(args.window, args.dry_run)))
            return 0
        parser.print_help()
        return 1
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({"status": "error", "message": str(error)}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
