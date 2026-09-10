from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import size


class CollectorTests(unittest.TestCase):
    def test_discovery_preserves_provenance_and_rejects_escapes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, tempfile.TemporaryDirectory() as external:
            root = Path(temporary)
            (root / "lua").mkdir()
            (root / "lua" / "config.lua").write_text("return {}")
            plugin = Path(external) / "store-plugin"
            (plugin / "lua").mkdir(parents=True)
            (plugin / "lua" / "plugin.lua").write_text("return {}")
            start = root / "pack" / "any-name" / "start"
            start.mkdir(parents=True)
            (start / "linked").symlink_to(plugin, target_is_directory=True)
            found = size.discover(root)
            self.assertEqual(
                [source.logical for source in found],
                [
                    ("config", "lua", "config.lua"),
                    ("plugins", "linked", "lua", "plugin.lua"),
                ],
            )
            escaped = plugin / "escaped.lua"
            escaped.symlink_to(Path(temporary) / "lua" / "config.lua")
            with self.assertRaisesRegex(size.AnalysisError, "escapes owner root"):
                size.discover(root)

    def test_discovery_rejects_cycles_and_ignores_non_lua_escapes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, tempfile.TemporaryDirectory() as external:
            root = Path(temporary)
            plugin = root / "pack" / "x" / "start" / "plugin"
            plugin.mkdir(parents=True)
            (plugin / "again").symlink_to(".")
            with self.assertRaisesRegex(size.AnalysisError, "cycle"):
                size.discover(root)
            (plugin / "again").unlink()
            (plugin / "parser.so").symlink_to("/nix/store/external-parser.so")
            queries = Path(external) / "queries"
            queries.mkdir()
            (queries / "highlights.scm").write_text("(identifier) @variable")
            (plugin / "queries").symlink_to(queries, target_is_directory=True)
            (plugin / "tests").mkdir()
            (plugin / "tests" / "invalid.lua").write_text("local function incomplete(")
            (plugin / "plugin.lua").write_text("return {}")
            self.assertEqual(
                [source.path.name for source in size.discover(root)],
                ["plugin.lua", "invalid.lua"],
            )

    def test_collect_emits_versioned_opaque_envelope(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            packpath = root / "packpath"
            packpath.mkdir()
            nvim = root / "nvim"
            nvim.write_bytes(b"nvim")
            path = root / "file.lua"
            path.write_bytes(b"return {}\n")
            source = size.Source(0, ("config", "lua", "file.lua"), path)
            observation = {
                "argv": [str(nvim)],
                "duration_ns": 1,
                "returncode": 1,
                "stdout": "partial",
                "stderr": "failure",
                "launch_error": None,
            }
            with patch("scripts.size.discover", return_value=[source]), patch(
                "scripts.size.probe", return_value=observation
            ):
                raw = size.collect(nvim, packpath)
        self.assertEqual(raw["format"], "poincare-size-raw/v1")
        self.assertEqual(raw["probe"], observation)
        self.assertEqual(raw["manifest"][0]["byte_length"], 10)
        self.assertEqual(len(raw["manifest"][0]["sha256"]), 64)
        self.assertEqual(raw["collector"]["nvim"]["resolved_path"], str(nvim))
        self.assertEqual(raw["collector"]["packpath"]["resolved_path"], str(packpath))

    def test_probe_invokes_neovim_once_and_retains_all_process_output(self) -> None:
        source = size.Source(0, ("config", "file.lua"), Path("file.lua"))
        result = subprocess.CompletedProcess([], 7, "not JSON", "diagnostic")
        with patch("scripts.size.subprocess.run", return_value=result) as run:
            observation = size.probe(Path("nvim"), [source])
        run.assert_called_once()
        command = run.call_args.args[0]
        self.assertEqual(
            command[1:8], ["-u", "NONE", "-i", "NONE", "--noplugin", "-n", "-l"]
        )
        self.assertEqual(observation["argv"], command)
        self.assertEqual(observation["returncode"], 7)
        self.assertEqual(observation["stdout"], "not JSON")
        self.assertEqual(observation["stderr"], "diagnostic")
        self.assertIsNone(observation["launch_error"])


if __name__ == "__main__":
    unittest.main()
