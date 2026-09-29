import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import simple_tile as tile


def window(address, cls='term', ws=2, **extra):
    return dict(address=address, **{'class': cls}, workspace={'id': ws}, mapped=True,
                at=[0, 0], size=[800, 600], floating=False, **extra)


class RestoreTests(unittest.TestCase):
    def test_browser_restore_requests_new_window_and_preserves_profile(self):
        app = {"argv": ["chrome", "--profile-directory=Work"], "name": "Chrome"}
        prepared = tile.app_for_restore(app, {"class": "google-chrome"})
        self.assertEqual(prepared["argv"], ["chrome", "--new-window", "--profile-directory=Work"])
        self.assertEqual(app["argv"], ["chrome", "--profile-directory=Work"])
        self.assertEqual(tile.app_for_restore(prepared, {"class": "google-chrome"})["argv"].count("--new-window"), 1)
        self.assertIs(tile.app_for_restore(app, {"class": "chrome-webapp-Default"}), app)

    def test_browser_restore_uses_installed_launcher_not_saved_exec(self):
        with tempfile.TemporaryDirectory() as directory:
            desktop = Path(directory) / "chrome.desktop"
            desktop.write_text('[Desktop Entry]\nExec=/opt/chrome --profile-directory="Work Profile" %U\n')
            app = {"desktop_path": str(desktop), "exec": "untrusted-command"}
            prepared = tile.app_for_restore(app, {"class": "google-chrome"})
        self.assertEqual(prepared["argv"], ["/opt/chrome", "--new-window", "--profile-directory=Work Profile"])
        app = {"exec": "untrusted-command"}
        self.assertIs(tile.app_for_restore(app, {"class": "google-chrome"}), app)

    def test_inactive_workspace_close_restores_both_chrome_windows(self):
        chrome = window("0x1", "google-chrome", ws=2)
        missing = window("0x2", "google-chrome", ws=2, title="Second")
        extra = window("0x99", "other", ws=2)
        active_window = window("0xaa", "editor", ws=1)
        app = {"class": "google-chrome", "name": "Google Chrome", "argv": ["chrome"]}
        settings = {"workspace_layouts": {2: {"windows": [chrome, missing], "apps": [app]}}}
        state = {"active": 1, "clients": [chrome, extra, active_window]}

        def hypr(*args):
            if args[0] == "activeworkspace":
                return json.dumps({"id": state["active"]})
            if args[0] == "clients":
                return json.dumps(state["clients"])
            if "focus({workspace=2})" in args[1]:
                state["active"] = 2
            elif "focus({workspace=1})" in args[1]:
                state["active"] = 1
            elif "window.close" in args[1]:
                self.assertIn("0x99", args[1])
                state["clients"].remove(extra)
            return "ok"

        def launch(argv, **kwargs):
            self.assertEqual(state["active"], 2)
            self.assertEqual(argv, ["chrome", "--new-window"])
            self.assertNotIn(extra, state["clients"])
            state["clients"].append(missing)

        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "runtime_lock"), patch.object(tile, "hypr", side_effect=hypr), \
                patch.object(tile, "is_app_available", return_value=(True, "ok")), \
                patch.object(tile.subprocess, "Popen", side_effect=launch) as popen, \
                patch.object(tile, "apply_layout_preset"), patch.object(tile, "restore_geometry") as geometry:
            result = tile.restore_workspace(2, conflict_action="close")
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["launched"], ["Google Chrome"])
        self.assertEqual(state["active"], 1)
        self.assertIn(active_window, state["clients"])
        self.assertEqual(len(geometry.call_args.args[1]), 2)
        popen.assert_called_once()

    def test_waits_for_matching_new_window_even_on_wrong_workspace(self):
        old = window('0x1')
        wrong = window('0x2', 'other')
        new = window('0x3', ws=9)
        with patch.object(tile, 'hypr', side_effect=[json.dumps([old, wrong]), json.dumps([old, wrong, new])]), patch.object(tile.time, 'sleep'):
            self.assertEqual(tile.wait_for_window({'class': 'term'}, {'0x1'}), new)

    def test_window_timeout(self):
        with patch.object(tile, 'hypr', return_value='[]'):
            self.assertIsNone(tile.wait_for_window({'class': 'term'}, set(), timeout=0))

    def test_duplicate_app_slots_are_matched_once_each(self):
        a, b = window('0x1', title='A'), window('0x2', title='B')
        slots = [dict(a), dict(b)]
        settings = {'workspace_layouts': {2: {'windows': slots, 'apps': [{'class': 'term'}]}}}
        def hypr(*args):
            return json.dumps({'id': 1}) if args[0] == 'activeworkspace' else json.dumps([b, a]) if args[0] == 'clients' else 'ok'
        with patch.object(tile, 'read_settings', return_value=settings), patch.object(tile, 'runtime_lock'), patch.object(tile, 'hypr', side_effect=hypr), patch.object(tile, 'restore_geometry') as restore, patch.object(tile, 'launch_app') as launch:
            result = tile.restore_workspace(2)
        self.assertEqual(result['status'], 'ok')
        self.assertEqual([c['address'] for _, c in restore.call_args.args[1]], ['0x1', '0x2'])
        launch.assert_not_called()

    def test_launched_window_is_moved_by_address(self):
        new = window('0x3', ws=9)
        target = window('0x3')
        settings = {'workspace_layouts': {2: {'apps': [{'class': 'term', 'argv': ['foot']}]}}}
        calls = ['[]', '{"id":1}', '[]', 'ok', 'ok', json.dumps([target]), 'ok']
        with patch.object(tile, 'read_settings', return_value=settings), patch.object(tile, 'runtime_lock'), patch.object(tile, 'hypr', side_effect=calls) as hypr, patch.object(tile, 'is_app_available', return_value=(True, 'ok')), patch.object(tile, 'launch_app', return_value=True), patch.object(tile, 'wait_for_window', return_value=new):
            result = tile.restore_workspace(2)
        self.assertEqual(result['status'], 'ok')
        hypr.assert_any_call('eval', tile.move_expression('0x3', 2, False))

    def test_missing_window_is_a_failure_not_launch_success(self):
        settings = {'workspace_layouts': {2: {'apps': [{'class': 'term'}]}}}
        with patch.object(tile, 'read_settings', return_value=settings), patch.object(tile, 'runtime_lock'), patch.object(tile, 'hypr', side_effect=['[]', '{"id":1}', '[]', 'ok', 'ok']), patch.object(tile, 'is_app_available', return_value=(True, 'ok')), patch.object(tile, 'launch_app', return_value=True), patch.object(tile, 'wait_for_window', return_value=None):
            result = tile.restore_workspace(2)
        self.assertEqual(result['status'], 'error')
        self.assertEqual(result['failed'][0]['reason'], 'window_timeout')

    def test_geometry_tree_preserves_app_positions_not_capture_order(self):
        left = {'class': 'left', 'at': [0, 0], 'size': [600, 600]}
        top = {'class': 'top', 'at': [610, 0], 'size': [390, 290]}
        bottom = {'class': 'bottom', 'at': [610, 300], 'size': [390, 300]}
        tree = tile.layout_tree([bottom, left, top])
        self.assertEqual(tree['axis'], 0)
        self.assertEqual(tree['left'], left)
        self.assertEqual(tree['right']['axis'], 1)
        self.assertEqual(tree['right']['left'], top)
        self.assertGreater(tree['ratio'], 1)

    def test_overlapping_geometry_rejected(self):
        with self.assertRaises(ValueError):
            tile.layout_tree([{'at': [0, 0], 'size': [100, 100]}] * 2)

    def test_autostart_once_per_session_and_retries_ipc_failure(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(tile, 'get_runtime_dir', return_value=Path(directory)), patch.object(tile, 'runtime_lock'), patch.dict(os.environ, {'HYPRLAND_INSTANCE_SIGNATURE': 'test-session'}), patch.object(tile, '_autostart_all', return_value={'status': 'ok', 'workspaces': [2]}) as run, patch.object(tile, 'hypr', side_effect=[RuntimeError('not ready'), '[]']):
            with self.assertRaises(RuntimeError):
                tile.autostart_all()
            self.assertEqual(tile.autostart_all()['status'], 'ok')
            self.assertEqual(tile.autostart_all()['status'], 'already_started')
            run.assert_called_once_with(False)

    def test_dry_run_does_not_dispatch_or_launch(self):
        settings = {'workspace_layouts': {2: {'apps': [{'class': 'term'}]}}}
        with patch.object(tile, 'read_settings', return_value=settings), patch.object(tile, 'runtime_lock'), patch.object(tile, 'hypr', side_effect=['[]', '{"id":1}']) as hypr, patch.object(tile, 'is_app_available', return_value=(True, 'ok')), patch.object(tile, 'launch_app') as launch:
            self.assertEqual(tile.restore_workspace(2, dry_run=True)['status'], 'ok')
        launch.assert_not_called()
        self.assertFalse(any(c.args[0] == 'eval' for c in hypr.call_args_list))

    def test_removed_app_is_not_restored_from_stale_window_slots(self):
        settings = {"workspace_layouts": {2: {"apps": [], "windows": [window("0x1")]}}}
        with patch.object(tile, "read_settings", return_value=settings), patch.object(tile, "runtime_lock"), patch.object(tile, "hypr") as hypr, patch.object(tile, "launch_app") as launch:
            self.assertEqual(tile.restore_workspace(2)["status"], "no_apps")
        launch.assert_not_called()
        hypr.assert_not_called()

    def test_detect_layout_preset(self):
        w1 = {"at": [0, 0], "size": [960, 1080]}
        w2 = {"at": [960, 0], "size": [960, 1080]}
        self.assertEqual(tile.detect_layout_preset([w1, w2]), "side-by-side")

        w_top = {"at": [0, 0], "size": [1920, 540]}
        w_bot = {"at": [0, 540], "size": [1920, 540]}
        self.assertEqual(tile.detect_layout_preset([w_top, w_bot]), "stacked")

        c1 = {"at": [0, 0], "size": [640, 1080]}
        c2 = {"at": [640, 0], "size": [640, 1080]}
        c3 = {"at": [1280, 0], "size": [640, 1080]}
        self.assertEqual(tile.detect_layout_preset([c1, c2, c3]), "columns")

        m_left = {"at": [0, 0], "size": [1000, 1080]}
        s_top = {"at": [1000, 0], "size": [920, 540]}
        s_bot = {"at": [1000, 540], "size": [920, 540]}
        self.assertEqual(tile.detect_layout_preset([m_left, s_top, s_bot]), "master-left")

    def test_align_tiled_windows_swaps_out_of_order_windows(self):
        saved1 = {"address": "0x1", "at": [0, 0], "size": [960, 1080]}
        saved2 = {"address": "0x2", "at": [960, 0], "size": [960, 1080]}
        # Live clients are swapped: client1 (0x1) is at 960, client2 (0x2) is at 0
        c1 = {"address": "0x1", "at": [960, 0], "size": [960, 1080], "workspace": {"id": 2}, "floating": False, "mapped": True}
        c2 = {"address": "0x2", "at": [0, 0], "size": [960, 1080], "workspace": {"id": 2}, "floating": False, "mapped": True}
        pairs = [(saved1, c1), (saved2, c2)]
        with patch.object(tile, "hypr") as mock_hypr:
            mock_hypr.side_effect = lambda *args: json.dumps([c1, c2]) if args[0] == "clients" else "ok"
            tile.align_tiled_windows(2, pairs)
            mock_hypr.assert_any_call("eval", 'hl.dispatch(hl.dsp.window.swap({window="address:0x1", with="address:0x2"}))')

    def test_restore_conflict_detected_on_ask(self):
        saved = window("0x1", "term", ws=2)
        extra = window("0x99", "browser", ws=2)
        settings = {"workspace_layouts": {2: {"windows": [saved], "apps": [{"class": "term"}]}}}
        clients = [saved, extra]
        def mock_hypr(*args):
            if args[0] == "activeworkspace":
                return json.dumps({"id": 1})
            if args[0] == "clients":
                return json.dumps(clients)
            return "ok"
        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "runtime_lock"), \
                patch.object(tile, "hypr", side_effect=mock_hypr):
            res = tile.restore_workspace(2, conflict_action="ask")
        self.assertEqual(res["status"], "conflict")
        self.assertEqual(res["workspace"], 2)
        self.assertEqual(res["conflict_count"], 1)
        self.assertEqual(res["conflicts"][0]["address"], "0x99")
        self.assertGreaterEqual(res["next_free_workspace"], 3)

    def test_restore_conflict_action_move(self):
        saved = window("0x1", "term", ws=2)
        extra = window("0x99", "browser", ws=2)
        settings = {"workspace_layouts": {2: {"windows": [saved], "apps": [{"class": "term"}]}}}
        calls = []
        clients_called = [0]
        def mock_hypr(*args):
            calls.append(args)
            if args[0] == "activeworkspace":
                return json.dumps({"id": 1})
            if args[0] == "clients":
                clients_called[0] += 1
                return json.dumps([saved, extra]) if clients_called[0] == 1 else json.dumps([saved])
            return "ok"
        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "runtime_lock"), \
                patch.object(tile, "hypr", side_effect=mock_hypr), \
                patch.object(tile, "send_notification") as notify, \
                patch.object(tile, "restore_geometry"):
            res = tile.restore_workspace(2, conflict_action="move")
        self.assertEqual(res["status"], "ok")
        notify.assert_called_once()
        self.assertTrue(any(c[0] == "eval" and "0x99" in c[1] for c in calls))

    def test_restore_conflict_action_close(self):
        saved = window("0x1", "term", ws=2)
        extra = window("0x99", "browser", ws=2)
        settings = {"workspace_layouts": {2: {"windows": [saved], "apps": [{"class": "term"}]}}}
        calls = []
        clients_called = [0]
        def mock_hypr(*args):
            calls.append(args)
            if args[0] == "activeworkspace":
                return json.dumps({"id": 1})
            if args[0] == "clients":
                clients_called[0] += 1
                return json.dumps([saved, extra]) if clients_called[0] == 1 else json.dumps([saved])
            return "ok"
        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "runtime_lock"), \
                patch.object(tile, "hypr", side_effect=mock_hypr), \
                patch.object(tile, "restore_geometry"):
            res = tile.restore_workspace(2, conflict_action="close")
        self.assertEqual(res["status"], "ok")
        self.assertTrue(any(c[0] == "eval" and "window.close" in c[1] and "0x99" in c[1] for c in calls))

    def test_close_on_inactive_workspace_waits_and_preserves_original_workspace(self):
        saved = window("0x1", "term", ws=2)
        extra = window("0x99", "browser", ws=2)
        untouched = window("0xaa", "editor", ws=1)
        settings = {"workspace_layouts": {2: {"windows": [saved], "apps": [{"class": "term"}]}}}
        state = {"active": 1, "closing": False, "polls": 0, "closed": False}
        calls = []

        def hypr(*args):
            calls.append(args)
            if args[0] == "activeworkspace":
                return json.dumps({"id": state["active"]})
            if args[0] == "clients":
                if state["closing"]:
                    state["polls"] += 1
                    state["closed"] = state["polls"] >= 3
                return json.dumps([saved, untouched] + ([] if state["closed"] else [extra]))
            if "focus({workspace=2})" in args[1]:
                state["active"] = 2
            elif "focus({workspace=1})" in args[1]:
                state["active"] = 1
            elif "window.close" in args[1]:
                self.assertEqual(state["active"], 2)
                self.assertIn("0x99", args[1])
                state["closing"] = True
            return "ok"

        def restore(ws, pairs):
            self.assertTrue(state["closed"], "layout must not start while conflicts are closing")
            self.assertEqual(ws, 2)
            self.assertEqual([c["address"] for _, c in pairs], ["0x1"])

        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "runtime_lock"), patch.object(tile, "hypr", side_effect=hypr), \
                patch.object(tile.time, "sleep"), patch.object(tile, "restore_geometry", side_effect=restore), \
                patch.object(tile, "launch_app") as launch:
            result = tile.restore_workspace(2, conflict_action="close")
        self.assertEqual(result["status"], "ok")
        self.assertEqual(state["active"], 1)
        launch.assert_not_called()
        self.assertFalse(any(c[0] == "eval" and "0xaa" in c[1] for c in calls))

    def test_close_confirmation_stops_restore_and_returns_to_original_workspace(self):
        saved = window("0x1", "term", ws=2)
        extra = window("0x99", "browser", ws=2)
        settings = {"workspace_layouts": {2: {"windows": [saved], "apps": [{"class": "term"}]}}}
        def hypr(*args):
            return json.dumps({"id": 1}) if args[0] == "activeworkspace" else json.dumps([saved, extra]) if args[0] == "clients" else "ok"
        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "runtime_lock"), patch.object(tile, "hypr", side_effect=hypr) as ipc, \
                patch.object(tile, "wait_for_closed_windows", return_value=([saved, extra], [extra])), \
                patch.object(tile, "restore_geometry") as geometry, patch.object(tile, "launch_app") as launch:
            result = tile.restore_workspace(2, conflict_action="close")
        self.assertEqual(result["status"], "error")
        self.assertEqual(result["workspace"], 2)
        self.assertEqual(result["failed"], [{"name": "browser", "reason": "close_timeout"}])
        geometry.assert_not_called()
        launch.assert_not_called()
        self.assertEqual(ipc.call_args.args, ("eval", 'hl.dispatch(hl.dsp.focus({workspace=1}))'))

    def test_wait_for_closed_windows_timeout_and_unmapped_clients(self):
        extra = window("0x99")
        with patch.object(tile, "hypr", return_value=json.dumps([extra])):
            clients, remaining = tile.wait_for_closed_windows({"0x99"}, timeout=0)
            self.assertEqual(remaining, [extra])
        extra["mapped"] = False
        with patch.object(tile, "hypr", return_value=json.dumps([extra])):
            clients, remaining = tile.wait_for_closed_windows({"0x99"}, timeout=0)
            self.assertEqual(remaining, [])

    def test_close_dry_run_does_not_focus_or_close_any_window(self):
        saved = window("0x1", "term", ws=2)
        extra = window("0x99", "browser", ws=2)
        settings = {"workspace_layouts": {2: {"windows": [saved], "apps": [{"class": "term"}]}}}
        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "runtime_lock"), \
                patch.object(tile, "hypr", side_effect=[json.dumps([saved, extra]), '{"id":1}']) as hypr, \
                patch.object(tile, "wait_for_closed_windows") as wait:
            result = tile.restore_workspace(2, dry_run=True, conflict_action="close")
        self.assertEqual(result["status"], "ok")
        self.assertFalse(any(c.args[0] == "eval" for c in hypr.call_args_list))
        wait.assert_not_called()

    def test_restore_conflict_action_keep(self):
        saved = window("0x1", "term", ws=2)
        extra = window("0x99", "browser", ws=2)
        settings = {"workspace_layouts": {2: {"windows": [saved], "apps": [{"class": "term"}]}}}
        calls = []
        clients_called = [0]
        def mock_hypr(*args):
            calls.append(args)
            if args[0] == "activeworkspace":
                return json.dumps({"id": 1})
            if args[0] == "clients":
                clients_called[0] += 1
                return json.dumps([saved, extra]) if clients_called[0] == 1 else json.dumps([saved, dict(extra, floating=True)])
            return "ok"
        with patch.object(tile, "read_settings", return_value=settings), \
                patch.object(tile, "runtime_lock"), \
                patch.object(tile, "hypr", side_effect=mock_hypr), \
                patch.object(tile, "restore_geometry"):
            res = tile.restore_workspace(2, conflict_action="keep")
        self.assertEqual(res["status"], "ok")
        self.assertTrue(any(c[0] == "eval" and "window.float" in c[1] and "0x99" in c[1] for c in calls))

    def test_find_next_free_workspace(self):
        c1 = {"workspace": {"id": 1}, "mapped": True, "hidden": False}
        c2 = {"workspace": {"id": 2}, "mapped": True, "hidden": False}
        with patch.object(tile, "hypr", return_value=json.dumps([c1, c2])):
            # Preferred start 1 should find 3
            self.assertEqual(tile.find_next_free_workspace(1), 3)
            # Preferred start 2 should find 3
            self.assertEqual(tile.find_next_free_workspace(2), 3)
            # Preferred start 4 should find 4
            self.assertEqual(tile.find_next_free_workspace(4), 4)



