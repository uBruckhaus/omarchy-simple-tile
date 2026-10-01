import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import simple_tile as tile


def client(address="0xaa", workspace=1, **values):
    return dict(address=address, workspace={"id": workspace}, mapped=True,
                floating=False, fullscreen=0, hidden=False, grouped=[], **values)


WORKSPACES = [{"id": 1, "monitor": "A"}, {"id": 2, "monitor": "A"},
              {"id": 3, "monitor": "B"}]


class PlanningTests(unittest.TestCase):
    def test_overflow_skips_app_preset_destination(self):
        clients = [client(), client("0xbb"), client("0xcc")]
        plan = tile.plan_move(clients, WORKSPACES, "0xcc", 2,
                              workspace_modes={2: "manual"})
        self.assertEqual(plan["target"], 4)

    def test_new_workspace_skips_inactive_app_preset(self):
        plan = tile.plan_move([client(), client("0xbb"), client("0xcc")],
                              WORKSPACES, "0xcc", 2,
                              workspace_modes={2: "manual", 4: "manual"})
        self.assertEqual(plan["target"], 5)

    def test_exact_cap_does_not_move(self):
        self.assertIsNone(tile.plan_move([client(), client("0xbb")], WORKSPACES, "0xaa", 2))

    def test_native_workspace_has_no_limit_even_with_a_saved_cap(self):
        clients = [client(f"0x{i:x}") for i in range(1, 9)]
        self.assertIsNone(tile.plan_move(clients, WORKSPACES, "0x8", 2,
                                        workspace_caps={1: 1},
                                        workspace_auto_presets={1: "none"}))

    def test_native_default_has_no_limit_but_explicit_preset_does(self):
        clients = [client(), client("0xbb"), client("0xcc")]
        self.assertIsNone(tile.plan_move(clients, WORKSPACES, "0xcc", 2,
                                        default_auto_presets={"2": "none"}))
        plan = tile.plan_move(clients, WORKSPACES, "0xcc", 2,
                              workspace_auto_presets={1: "side-by-side"},
                              default_auto_presets={"2": "none"})
        self.assertEqual(plan["target"], 2)

    def test_native_overflow_destination_is_not_bound_to_its_saved_cap(self):
        self.assertEqual(tile.pick_target_ws(WORKSPACES, {1: 3, 2: 8}, 1, 2,
                                             {2: 1}, {2: "none"}), 2)

    def test_only_new_window_is_targeted(self):
        plan = tile.plan_move([client(), client("0xbb"), client("0xcc")], WORKSPACES, "0xcc", 2)
        self.assertEqual(plan, {"address": "0xcc", "source": 1, "target": 2})

    def test_float_fullscreen_hidden_and_unmapped_do_not_count(self):
        for flag, value in [("floating", True), ("fullscreen", 2),
                            ("mapped", False), ("hidden", True)]:
            with self.subTest(flag=flag):
                ignored = client("0xbb")
                ignored[flag] = value
                self.assertEqual(tile.tiling_counts([client(), ignored]), {1: 1})

    def test_all_negative_workspaces_are_ignored(self):
        for workspace in [-1, -98, -1337, 0]:
            self.assertFalse(tile.is_tiled(client(workspace=workspace)))
            self.assertIsNone(tile.pick_target_ws(WORKSPACES, {}, workspace, 2))

    def test_grouped_window_is_not_moved(self):
        grouped = client()
        grouped["grouped"] = ["0xaa", "0xbb"]
        self.assertIsNone(tile.plan_move([grouped, client("0xbb")], WORKSPACES, "0xaa", 1))

    def test_new_workspace_skips_other_monitor(self):
        self.assertEqual(tile.pick_target_ws(WORKSPACES, {1: 3, 2: 2}, 1, 2), 4)

    def test_existing_room_on_same_monitor(self):
        self.assertEqual(tile.pick_target_ws(WORKSPACES, {1: 3, 2: 1}, 1, 2), 2)

    def test_never_scans_backwards(self):
        self.assertEqual(tile.pick_target_ws(WORKSPACES, {}, 2, 2), 4)

    def test_unknown_workspace_is_ignored(self):
        self.assertIsNone(tile.pick_target_ws(WORKSPACES, {}, 99, 2))

    def test_address_validation_blocks_code_injection(self):
        self.assertEqual(tile.normalize_addr("0xAB12"), "0xab12")
        for value in ["", 'aa\"}); os.exit()', "address:0xaa", "../aa"]:
            with self.assertRaises(ValueError):
                tile.move_expression(value, 2, False)

    def test_dispatch_targets_address_without_focusing(self):
        code = tile.move_expression("aa", 4, False)
        self.assertIn('window="address:0xaa"', code)
        self.assertIn('workspace="4"', code)
        self.assertIn("follow=false", code)
        self.assertNotIn("focus(", code)


    def test_workspace_specific_cap_allows_more_windows(self):
        clients = [client(), client("0xbb"), client("0xcc")]
        # Global cap is 2, but workspace 1 has custom cap 3. 3 windows should not move.
        self.assertIsNone(tile.plan_move(clients, WORKSPACES, "0xcc", 2, {1: 3}))

    def test_workspace_specific_cap_moves_earlier(self):
        clients = [client(workspace=2), client("0xbb", workspace=2)]
        # Global cap is 2, but workspace 2 has custom cap 1. 2nd window should move.
        plan = tile.plan_move(clients, WORKSPACES, "0xbb", 2, {2: 1})
        self.assertEqual(plan, {"address": "0xbb", "source": 2, "target": 4})

    def test_target_workspace_skips_full_workspace_with_custom_cap(self):
        # Workspaces: 1 (source), 2 (same monitor, 1 window), 3 (monitor B)
        # Workspace 2 has custom cap of 1, so with 1 window it is already full.
        counts = {1: 3, 2: 1}
        target = tile.pick_target_ws(WORKSPACES, counts, 1, 2, {2: 1})
        # Should skip workspace 2 and allocate next available ID on monitor A (4).
        self.assertEqual(target, 4)


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.environment = patch.dict(os.environ, {"XDG_RUNTIME_DIR": self.directory.name,
                                                    "XDG_CONFIG_HOME": self.directory.name})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.path = Path(self.directory.name) / "omarchy/shell.json"
        self.path.parent.mkdir()
        self.write_settings({"id": tile.PLUGIN_ID})

    def write_settings(self, entry):
        self.path.write_text(json.dumps({"bar": {"layout": {"right": [entry]}}}))

    def test_invalid_caps_fall_back(self):
        for cap in [0, 5, 8, 9, "3", True, None]:
            self.write_settings({"id": tile.PLUGIN_ID, "maxWindows": cap})
            self.assertEqual(tile.read_settings()["cap"], 2)

    def test_workspace_caps_parsing(self):
        self.write_settings({
            "id": tile.PLUGIN_ID,
            "maxWindows": 3,
            "workspaceCaps": {
                "1": 4,
                "2": 1,
                "invalid": 2,
                "0": 2,
                "-1": 2,
                "3": 0,
                "4": 9,
                "5": "2",
                "6": True,
                "7": 5,
            }
        })
        settings = tile.read_settings()
        self.assertEqual(settings["cap"], 3)
        self.assertEqual(settings["workspace_caps"], {1: 4, 2: 1})

    def test_paused_and_removed_plugins_do_not_query_or_move(self):
        for entry in [{"id": tile.PLUGIN_ID, "active": False}, {"id": "another.plugin"}]:
            self.write_settings(entry)
            with patch.object(tile, "hypr") as hypr:
                self.assertEqual(tile.handle_open("0xaa")["status"], "paused")
                hypr.assert_not_called()

    def test_dry_run_never_dispatches(self):
        clients = [client(), client("0xbb"), client("0xcc")]
        with patch.object(tile, "hypr", side_effect=[json.dumps(clients), json.dumps(WORKSPACES)]) as hypr:
            self.assertEqual(tile.handle_open("0xaa", True)["status"], "planned")
            self.assertEqual(hypr.call_count, 2)

    def test_native_open_does_not_move_or_reapply_layout(self):
        self.write_settings({"id": tile.PLUGIN_ID, "maxWindows": 1,
                             "workspaceCaps": {"1": 2},
                             "workspaceAutoPresets": {"1": "none"}})
        clients = [client(f"0x{i:x}") for i in range(1, 9)]
        with patch.object(tile, "hypr", side_effect=[json.dumps(clients), json.dumps(WORKSPACES)]) as hypr, \
                patch.object(tile, "apply_layout_preset") as apply:
            self.assertEqual(tile.handle_open("0x8")["status"], "unchanged")
            self.assertFalse(any(call.args[0] == "eval" for call in hypr.call_args_list))
            apply.assert_not_called()

    def test_workspace_caps_applied_in_handle_open(self):
        # Global cap 2, workspace 1 cap 3. 3 windows on workspace 1.
        self.write_settings({"id": tile.PLUGIN_ID, "maxWindows": 2, "workspaceCaps": {"1": 3}})
        clients = [client(), client("0xbb"), client("0xcc")]
        with patch.object(tile, "hypr", side_effect=[json.dumps(clients), json.dumps(WORKSPACES)]):
            self.assertEqual(tile.handle_open("0xcc", True)["status"], "unchanged")

    def test_missing_window_retry_is_bounded(self):
        with patch.object(tile, "hypr", return_value="[]") as hypr, patch.object(tile.time, "sleep"):
            self.assertEqual(tile.handle_open("0xaa")["status"], "unchanged")
            self.assertEqual(hypr.call_count, 5)

    def test_unconfirmed_move_is_an_error(self):
        clients = [client(), client("0xbb"), client("0xcc")]
        results = [json.dumps(clients), json.dumps(WORKSPACES), "error", json.dumps(clients)]
        with patch.object(tile, "hypr", side_effect=results):
            with self.assertRaisesRegex(RuntimeError, "not confirmed"):
                tile.handle_open("0xaa")

    def test_overflow_always_follows_even_with_legacy_follow_disabled(self):
        self.write_settings({"id": tile.PLUGIN_ID, "maxWindows": 2, "follow": False,
                             "workspaceAutoPresets": {"1": "side-by-side"}})
        before = [client(), client("0xbb"), client("0xcc")]
        after = [client(workspace=2), client("0xbb"), client("0xcc")]
        results = [json.dumps(before), json.dumps(WORKSPACES), "ok", json.dumps(after)]
        with patch.object(tile, "hypr", side_effect=results) as hypr:
            self.assertEqual(tile.handle_open("0xaa")["status"], "moved")
            dispatch = next(call.args[1] for call in hypr.call_args_list if call.args[0] == "eval")
            self.assertIn('workspace="2", follow=true', dispatch)

    def test_success_is_verified_and_duplicate_event_does_nothing(self):
        before = [client(), client("0xbb"), client("0xcc")]
        after = [client(workspace=2), client("0xbb"), client("0xcc")]
        results = [json.dumps(before), json.dumps(WORKSPACES), "ok", json.dumps(after),
                   json.dumps(after), json.dumps(WORKSPACES)]
        with patch.object(tile, "hypr", side_effect=results) as hypr:
            self.assertEqual(tile.handle_open("0xaa")["status"], "moved")
            self.assertEqual(tile.handle_open("0xaa")["status"], "unchanged")
            self.assertEqual(sum(call.args[0] == "eval" for call in hypr.call_args_list), 1)


class LockSecurityTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.runtime_dir = Path(self.directory.name) / "runtime"
        self.runtime_dir.mkdir(mode=0o700)
        self.config_dir = Path(self.directory.name) / "config"
        self.config_dir.mkdir(mode=0o700)
        self.environment = patch.dict(os.environ, {
            "XDG_RUNTIME_DIR": str(self.runtime_dir),
            "XDG_CONFIG_HOME": str(self.config_dir)
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)
        shell_path = self.config_dir / "omarchy/shell.json"
        shell_path.parent.mkdir(parents=True, exist_ok=True)
        shell_path.write_text(json.dumps({"bar": {"layout": {"right": [{"id": tile.PLUGIN_ID, "active": True, "maxWindows": 2}]}}}))

    def test_lock_does_not_truncate_existing_content(self):
        lock_file = self.runtime_dir / "omarchy-simple-tile.lock"
        lock_file.write_bytes(b"EXISTING_LOCK_CONTENT_PRESERVE")
        clients = [client(), client("0xbb"), client("0xcc")]
        with patch.object(tile, "hypr", side_effect=[json.dumps(clients), json.dumps(WORKSPACES)]):
            res = tile.handle_open("0xaa", dry_run=True)
            self.assertEqual(res["status"], "planned")
        self.assertEqual(lock_file.read_bytes(), b"EXISTING_LOCK_CONTENT_PRESERVE")

    def test_reject_symlink_lock_path(self):
        target_file = Path(self.directory.name) / "secret.txt"
        target_file.write_text("SENSITIVE_USER_DATA")
        lock_file = self.runtime_dir / "omarchy-simple-tile.lock"
        lock_file.symlink_to(target_file)
        with self.assertRaisesRegex(RuntimeError, "unsafe pre-existing"):
            with tile.runtime_lock():
                pass
        self.assertEqual(target_file.read_text(), "SENSITIVE_USER_DATA")

    def test_reject_symlinked_runtime_directory(self):
        real_dir = Path(self.directory.name) / "real_dir"
        real_dir.mkdir(mode=0o700)
        symlink_runtime = Path(self.directory.name) / "symlink_runtime"
        symlink_runtime.symlink_to(real_dir)
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(symlink_runtime)}):
            with self.assertRaisesRegex(RuntimeError, "unsafe symlinked"):
                tile.get_runtime_dir()

    def test_fallback_runtime_directory_symlink_rejection(self):
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": ""}):
            with patch.object(Path, "lstat") as mock_lstat, patch.object(Path, "is_symlink", return_value=True):
                with self.assertRaisesRegex(RuntimeError, "unsafe pre-existing symlinked"):
                    tile.get_runtime_dir()

    def test_fallback_runtime_directory_insecure_permissions(self):
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": ""}):
            mock_stat = type("Stat", (), {"st_mode": 0o777, "st_uid": os.getuid()})()
            with patch.object(Path, "lstat", return_value=mock_stat), patch.object(Path, "is_symlink", return_value=False), patch("stat.S_ISDIR", return_value=True):
                with self.assertRaisesRegex(RuntimeError, "unsafe runtime directory permissions"):
                    tile.get_runtime_dir()


class ManualModeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.runtime_dir = Path(self.directory.name) / "runtime"
        self.runtime_dir.mkdir(mode=0o700)
        self.config_dir = Path(self.directory.name) / "config"
        self.config_dir.mkdir(mode=0o700)
        self.environment = patch.dict(os.environ, {
            "XDG_RUNTIME_DIR": str(self.runtime_dir),
            "XDG_CONFIG_HOME": str(self.config_dir)
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.shell_path = self.config_dir / "omarchy/shell.json"
        self.shell_path.parent.mkdir(parents=True, exist_ok=True)

    def write_settings(self, entry):
        self.shell_path.write_text(json.dumps({"bar": {"layout": {"right": [entry]}}}))

    def test_manual_mode_in_plan_move_blocks_moves(self):
        clients = [client(workspace=2), client("0xbb", workspace=2), client("0xcc", workspace=2)]
        # Workspace 2 has cap 1, but is in manual mode
        plan = tile.plan_move(clients, WORKSPACES, "0xcc", 1, workspace_modes={2: "manual"})
        self.assertIsNone(plan)

    def test_manual_mode_in_handle_open(self):
        self.write_settings({
            "id": tile.PLUGIN_ID,
            "active": True,
            "maxWindows": 1,
            "workspaceModes": {"2": "manual"}
        })
        clients = [client(workspace=2), client("0xbb", workspace=2)]
        with patch.object(tile, "hypr", side_effect=[json.dumps(clients), json.dumps(WORKSPACES)]):
            res = tile.handle_open("0xbb", dry_run=True)
            self.assertEqual(res, {"status": "manual", "workspace": 2})

    def test_settings_parses_workspace_modes_and_layouts(self):
        self.write_settings({
            "id": tile.PLUGIN_ID,
            "maxWindows": 2,
            "workspaceModes": {"1": "auto", "2": "manual", "bad": "manual"},
            "workspaceLayouts": {
                "2": {
                    "mode": "manual",
                    "saveApps": True,
                    "autostart": True,
                    "apps": [{"name": "TestApp", "class": "test", "icon": "test"}]
                }
            }
        })
        settings = tile.read_settings()
        self.assertEqual(settings["workspace_modes"], {1: "auto", 2: "manual"})
        self.assertIn(2, settings["workspace_layouts"])
        self.assertEqual(settings["workspace_layouts"][2]["apps"][0]["name"], "TestApp")


class DesktopResolutionTests(unittest.TestCase):
    def test_resolve_app_by_startup_class(self):
        desktop_apps = [{
            "name": "Editor",
            "startup_class": "code-oss",
            "desktop_id": "code",
            "icon": "code",
            "desktop_path": "/usr/share/applications/code.desktop"
        }]
        c = {"class": "code-oss", "initialClass": "code-oss", "pid": 0}
        app = tile.resolve_app_for_client(c, desktop_apps)
        self.assertEqual(app["name"], "Editor")
        self.assertEqual(app["icon"], "code")

    def test_resolve_app_by_desktop_id(self):
        desktop_apps = [{
            "name": "Browser",
            "startup_class": "",
            "desktop_id": "firefox",
            "icon": "firefox",
            "desktop_path": "/usr/share/applications/firefox.desktop"
        }]
        c = {"class": "firefox", "initialClass": "firefox", "pid": 0}
        app = tile.resolve_app_for_client(c, desktop_apps)
        self.assertEqual(app["name"], "Browser")

    def test_resolve_app_fallback(self):
        c = {"class": "custom-tool", "initialClass": "custom-tool", "pid": 0}
        app = tile.resolve_app_for_client(c, [])
        self.assertEqual(app["name"], "Custom-tool")
        self.assertEqual(app["class"], "custom-tool")
        self.assertEqual(app["icon"], "custom-tool")

    def test_capture_workspace(self):
        clients = [
            {"address": "0x11", "workspace": {"id": 1}, "mapped": True, "class": "term",
             "title": "Terminal", "at": [0, 0], "size": [800, 600], "floating": False, "pid": 0},
            {"address": "0x22", "workspace": {"id": 2}, "mapped": True, "class": "browser",
             "title": "Web", "at": [0, 0], "size": [800, 600], "floating": False, "pid": 0},
        ]
        with patch.object(tile, "hypr", return_value=json.dumps(clients)), \
                patch.object(tile, "parse_desktop_files", return_value=[]), \
                patch.object(tile, "read_settings", return_value={}), \
                patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": ""}):
            res = tile.capture_workspace(1)
            self.assertEqual(res["status"], "ok")
            self.assertEqual(res["workspace"], 1)
            self.assertEqual(res["count"], 1)
            self.assertEqual(res["windows"][0]["address"], "0x11")
            self.assertEqual(res["apps"][0]["class"], "term")


class AppLaunchTests(unittest.TestCase):
    def setUp(self):
        lock = patch.object(tile, "runtime_lock")
        lock.start()
        self.addCleanup(lock.stop)

    def test_launch_standalone_argv(self):
        app = {"argv": ["/opt/bin/my-app", "--flag"]}
        with patch.object(tile.subprocess, "Popen") as popen:
            self.assertTrue(tile.launch_app(app))
            popen.assert_called_once()
            self.assertEqual(popen.call_args[0][0], ["/opt/bin/my-app", "--flag"])

    def test_launch_desktop_with_uwsm(self):
        app = {"desktop_path": "/usr/share/applications/test.desktop"}
        with patch.object(tile.shutil, "which", return_value="/usr/bin/uwsm-app"), \
                patch.object(tile.subprocess, "Popen") as popen:
            self.assertTrue(tile.launch_app(app))
            popen.assert_called_once_with(
                ["uwsm-app", "--", "/usr/share/applications/test.desktop"],
                stdout=tile.subprocess.DEVNULL,
                stderr=tile.subprocess.DEVNULL,
                start_new_session=True,
                env=popen.call_args[1]["env"]
            )

    def test_launch_app_rejects_raw_exec(self):
        # A raw exec command without desktop_path or argv must never execute
        app = {"exec": "rm -rf /"}
        with patch.object(tile.subprocess, "Popen") as popen:
            self.assertFalse(tile.launch_app(app))
            popen.assert_not_called()

    def test_restore_workspace_skips_already_running(self):
        app1 = {"name": "Term", "class": "term", "desktop_path": "/app/term.desktop"}
        app2 = {"name": "Editor", "class": "editor", "desktop_path": "/app/editor.desktop"}
        settings = {
            "workspace_layouts": {
                2: {
                    "mode": "manual",
                    "apps": [app1, app2]
                }
            }
        }
        # Term is already running on workspace 2
        clients = [{"address": "0x1", "workspace": {"id": 2}, "mapped": True, "class": "term"}]
        editor = {"address": "0x2", "workspace": {"id": 2}, "mapped": True, "class": "editor"}
        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "hypr", side_effect=[json.dumps(clients), json.dumps({"id": 1}), json.dumps(clients), json.dumps(clients), "ok", json.dumps(clients + [editor]), "ok"]), \
                patch.object(tile, "wait_for_window", return_value=editor), \
                patch.object(tile, "is_app_available", return_value=(True, "ok")), \
                patch.object(tile, "launch_app", return_value=True) as launch:
            res = tile.restore_workspace(2, dry_run=False)
            self.assertEqual(res["status"], "ok")
            self.assertIn("Term", res["already_running"])
            self.assertIn("Editor", res["launched"])
            launch.assert_called_once_with(app2)

    def test_autostart_all_triggers_enabled_workspaces(self):
        settings = {
            "workspace_layouts": {
                1: {"autostart": False, "apps": []},
                2: {"autostart": True, "apps": [{"name": "App2", "class": "app2"}]},
                3: {"autostart": True, "apps": [{"name": "App3", "class": "app3"}]},
            }
        }
        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "restore_workspace", return_value={"status": "ok"}) as restore:
            res = tile.autostart_all(dry_run=True)
            self.assertEqual(res["status"], "ok")
            self.assertEqual(len(res["workspaces"]), 2)
            restore.assert_any_call(2, dry_run=True)
            restore.assert_any_call(3, dry_run=True)


    def test_is_app_available_checks_command_and_desktop(self):
        # Binary in argv exists
        with patch.object(tile.shutil, "which", return_value="/usr/bin/python3"):
            avail, reason = tile.is_app_available({"argv": ["python3"]})
            self.assertTrue(avail)
            self.assertEqual(reason, "ok")

        # Missing binary in argv
        with patch.object(tile.shutil, "which", return_value=None):
            avail, reason = tile.is_app_available({"argv": ["nonexistent_xyz_app"]})
            self.assertFalse(avail)
            self.assertEqual(reason, "command_not_found")

        # Missing desktop file
        avail, reason = tile.is_app_available({"desktop_path": "/nonexistent/path.desktop"})
        self.assertFalse(avail)
        self.assertEqual(reason, "desktop_file_not_found")

    def test_restore_workspace_handles_missing_app_gracefully(self):
        valid_app = {"name": "GoodApp", "class": "good", "desktop_path": "/app/good.desktop"}
        missing_app = {"name": "MissingApp", "class": "missing", "desktop_path": "/nonexistent/bad.desktop"}
        settings = {
            "workspace_layouts": {
                2: {
                    "mode": "manual",
                    "apps": [missing_app, valid_app]
                }
            }
        }
        clients = []
        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "hypr", side_effect=["[]", json.dumps({"id": 1}), "[]", "ok", json.dumps([{"address": "0x2", "workspace": {"id": 2}, "mapped": True, "class": "good"}]), "ok"]), \
                patch.object(tile, "wait_for_window", return_value={"address": "0x2", "workspace": {"id": 2}, "mapped": True, "class": "good"}), \
                patch.object(tile, "is_app_available", side_effect=[(False, "desktop_file_not_found"), (True, "ok")]), \
                patch.object(tile, "launch_app", return_value=True) as launch:
            res = tile.restore_workspace(2, dry_run=False)
            self.assertEqual(res["status"], "partial")
            self.assertEqual(res["launched"], ["GoodApp"])
            self.assertEqual(len(res["failed"]), 1)
            self.assertEqual(res["failed"][0]["name"], "MissingApp")
            self.assertEqual(res["failed"][0]["reason"], "desktop_file_not_found")
            # launch_app must only be called for GoodApp, not for MissingApp
            launch.assert_called_once_with(valid_app)

    def test_restore_workspace_all_failed_returns_error(self):
        missing_app = {"name": "MissingApp", "class": "missing", "desktop_path": "/nonexistent/bad.desktop"}
        settings = {
            "workspace_layouts": {
                2: {
                    "mode": "manual",
                    "apps": [missing_app]
                }
            }
        }
        clients = []
        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "hypr", side_effect=[json.dumps(clients), json.dumps({"id": 1})]), \
                patch.object(tile, "is_app_available", return_value=(False, "desktop_file_not_found")):
            res = tile.restore_workspace(2, dry_run=False)
            self.assertEqual(res["status"], "error")
            self.assertEqual(len(res["failed"]), 1)
            self.assertEqual(res["launched"], [])

    def test_apply_layout_preset_side_by_side_and_stacked(self):
        # 2 windows stacked vertically (dy > dx)
        c1 = {"workspace": {"id": 1}, "mapped": True, "at": [0, 0]}
        c2 = {"workspace": {"id": 1}, "mapped": True, "at": [0, 500]}
        clients = [c1, c2]

        with patch.object(tile, "hypr", return_value=json.dumps(clients)) as mock_hypr:
            res = tile.apply_layout_preset(1, "side-by-side", dry_run=False)
            self.assertEqual(res["status"], "ok")
            # Should have called togglesplit because it was stacked
            called_lua = [call.args[1] for call in mock_hypr.call_args_list if len(call.args) > 1]
            self.assertTrue(any('togglesplit' in lua for lua in called_lua))

        # 2 windows side-by-side (dx > dy)
        c1_side = {"workspace": {"id": 1}, "mapped": True, "at": [0, 0]}
        c2_side = {"workspace": {"id": 1}, "mapped": True, "at": [960, 0]}
        clients_side = [c1_side, c2_side]

        with patch.object(tile, "hypr", return_value=json.dumps(clients_side)) as mock_hypr:
            res = tile.apply_layout_preset(1, "stacked", dry_run=False)
            self.assertEqual(res["status"], "ok")
            # Should have called togglesplit because it was side-by-side
            called_lua = [call.args[1] for call in mock_hypr.call_args_list if len(call.args) > 1]
            self.assertTrue(any('togglesplit' in lua for lua in called_lua))

    def test_apply_layout_preset_master_orientations(self):
        c1 = {"workspace": {"id": 1}, "mapped": True, "at": [0, 0]}
        c2 = {"workspace": {"id": 1}, "mapped": True, "at": [960, 0]}
        c3 = {"workspace": {"id": 1}, "mapped": True, "at": [960, 500]}
        clients = [c1, c2, c3]

        with patch.object(tile, "hypr", return_value=json.dumps(clients)) as mock_hypr:
            res = tile.apply_layout_preset(1, "master-right", dry_run=False)
            self.assertEqual(res["status"], "ok")
            called_lua = [call.args[1] for call in mock_hypr.call_args_list if len(call.args) > 1]
            self.assertTrue(any('orientationright' in lua for lua in called_lua))

        with patch.object(tile, "hypr", return_value=json.dumps(clients)) as mock_hypr:
            res = tile.apply_layout_preset(1, "columns", dry_run=False)
            self.assertEqual(res["status"], "ok")
            called_lua = [call.args[1] for call in mock_hypr.call_args_list if len(call.args) > 1]
            self.assertTrue(any('orientationcenter' in lua for lua in called_lua))

    def test_apply_layout_preset_columns_4_windows(self):
        c1 = {"workspace": {"id": 1}, "mapped": True, "address": "0x1", "at": [0, 0], "size": [960, 1080]}
        c2 = {"workspace": {"id": 1}, "mapped": True, "address": "0x2", "at": [960, 0], "size": [960, 540]}
        c3 = {"workspace": {"id": 1}, "mapped": True, "address": "0x3", "at": [960, 540], "size": [480, 540]}
        c4 = {"workspace": {"id": 1}, "mapped": True, "address": "0x4", "at": [1440, 540], "size": [480, 540]}
        clients = [c1, c2, c3, c4]

        with patch.object(tile, "hypr", return_value=json.dumps(clients)) as mock_hypr:
            res = tile.apply_layout_preset(1, "columns", dry_run=False)
            self.assertEqual(res["status"], "ok")
            called_lua = [call.args[1] for call in mock_hypr.call_args_list if len(call.args) > 1]
            # Must configure dwindle layout rule
            self.assertTrue(any('layout = "dwindle"' in lua for lua in called_lua))
            # Must NOT use orientationcenter (which would stack slaves)
            self.assertFalse(any('orientationcenter' in lua for lua in called_lua))
            # Must invoke togglesplit on stacked windows
            self.assertTrue(any('togglesplit' in lua for lua in called_lua))

    def test_apply_layout_preset_columns_cap4_empty_workspace(self):
        clients = []
        settings = {"cap": 2, "workspace_caps": {1: 4}}
        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "hypr", return_value=json.dumps(clients)) as mock_hypr:
            res = tile.apply_layout_preset(1, "columns", dry_run=False)
            self.assertEqual(res["status"], "ok")
            called_lua = [call.args[1] for call in mock_hypr.call_args_list if len(call.args) > 1]
            self.assertTrue(any('layout = "dwindle"' in lua for lua in called_lua))

    def test_apply_preset_cli_flag(self):
        clients = []
        with patch.object(tile, "hypr", return_value=json.dumps(clients)), \
                patch("sys.stdout") as mock_stdout:
            exit_code = tile.main(["--apply-preset", "3", "master-left", "--dry-run"])
            self.assertEqual(exit_code, 0)

    def test_apply_layout_preset_none(self):
        # 3 clients present; preset none should only set dwindle workspace rule and perform no layout adjustments
        c1 = {"workspace": {"id": 2}, "mapped": True, "at": [0, 0]}
        c2 = {"workspace": {"id": 2}, "mapped": True, "at": [960, 0]}
        c3 = {"workspace": {"id": 2}, "mapped": True, "at": [960, 500]}
        clients = [c1, c2, c3]

        with patch.object(tile, "hypr", return_value=json.dumps(clients)) as mock_hypr:
            res = tile.apply_layout_preset(2, "none", dry_run=False)
            self.assertEqual(res["status"], "ok")
            self.assertEqual(res["preset"], "none")
            called_lua = [call.args[1] for call in mock_hypr.call_args_list if len(call.args) > 1 and call.args[0] == "eval"]
            self.assertEqual(len(called_lua), 1)
            self.assertIn('layout = "dwindle"', called_lua[0])
            self.assertFalse(any("togglesplit" in lua for lua in called_lua))
            self.assertFalse(any("orientation" in lua for lua in called_lua))

    def test_remove_preset_cli_flag(self):
        clients = []
        with patch.object(tile, "hypr", return_value=json.dumps(clients)) as mock_hypr, \
                patch("sys.stdout"):
            exit_code = tile.main(["--remove-preset", "2", "--dry-run"])
            self.assertEqual(exit_code, 0)

    def test_remove_all_presets(self):
        workspaces = [{"id": 1}, {"id": 2}]
        with patch.object(tile, "hypr", side_effect=[json.dumps(workspaces), "[]", "[]"]):
            res = tile.remove_all_presets(dry_run=True)
            self.assertEqual(res["status"], "ok")
            self.assertEqual(res["action"], "remove_all_presets")
            self.assertEqual(res["workspaces"], [1, 2])

    def test_reset_all_presets(self):
        workspaces = [{"id": 1}, {"id": 2}]
        settings = {"cap": 2, "default_auto_presets": {"2": "side-by-side"}}
        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "hypr", side_effect=[json.dumps(workspaces), "[]", "[]"]):
            res = tile.reset_all_presets(dry_run=True)
            self.assertEqual(res["status"], "ok")
            self.assertEqual(res["action"], "reset_all_presets")
            self.assertEqual(res["default_preset"], "side-by-side")

    def test_clear_app_preset(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir) / "omarchy/shell.json"
            config_path.parent.mkdir(parents=True, exist_ok=True)
            config_data = {
                "bar": {
                    "layout": {
                        "right": [
                            {
                                "id": tile.PLUGIN_ID,
                                "workspaceLayouts": {"2": {"apps": [{"name": "app"}]}},
                                "workspaceModes": {"2": "manual"}
                            }
                        ]
                    }
                }
            }
            config_path.write_text(json.dumps(config_data))
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": tmpdir}):
                res = tile.clear_app_preset(2)
                self.assertEqual(res["status"], "ok")
                self.assertTrue(res["cleared"])
                updated = json.loads(config_path.read_text())
                entry = updated["bar"]["layout"]["right"][0]
                self.assertNotIn("2", entry.get("workspaceLayouts", {}))
                self.assertNotIn("2", entry.get("workspaceModes", {}))

    def test_clear_all_app_presets(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir) / "omarchy/shell.json"
            config_path.parent.mkdir(parents=True, exist_ok=True)
            config_data = {
                "bar": {
                    "layout": {
                        "right": [
                            {
                                "id": tile.PLUGIN_ID,
                                "workspaceLayouts": {"2": {"apps": []}, "3": {"apps": []}},
                                "workspaceModes": {"2": "manual", "3": "manual", "1": "auto"}
                            }
                        ]
                    }
                }
            }
            config_path.write_text(json.dumps(config_data))
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": tmpdir}):
                res = tile.clear_all_app_presets()
                self.assertEqual(res["status"], "ok")
                updated = json.loads(config_path.read_text())
                entry = updated["bar"]["layout"]["right"][0]
                self.assertEqual(entry.get("workspaceLayouts"), {})
                self.assertEqual(entry.get("workspaceModes"), {"1": "auto"})


if __name__ == "__main__":
    unittest.main()
