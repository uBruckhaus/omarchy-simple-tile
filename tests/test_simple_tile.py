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
    def test_exact_cap_does_not_move(self):
        self.assertIsNone(tile.plan_move([client(), client("0xbb")], WORKSPACES, "0xaa", 2))

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
        for cap in [0, 9, "3", True, None]:
            self.write_settings({"id": tile.PLUGIN_ID, "maxWindows": cap})
            self.assertEqual(tile.read_settings()["cap"], 2)

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

    def test_success_is_verified_and_duplicate_event_does_nothing(self):
        before = [client(), client("0xbb"), client("0xcc")]
        after = [client(workspace=2), client("0xbb"), client("0xcc")]
        results = [json.dumps(before), json.dumps(WORKSPACES), "ok", json.dumps(after),
                   json.dumps(after), json.dumps(WORKSPACES)]
        with patch.object(tile, "hypr", side_effect=results) as hypr:
            self.assertEqual(tile.handle_open("0xaa")["status"], "moved")
            self.assertEqual(tile.handle_open("0xaa")["status"], "unchanged")
            self.assertEqual(sum(call.args[0] == "eval" for call in hypr.call_args_list), 1)


if __name__ == "__main__":
    unittest.main()
