from __future__ import annotations

import io
import json
import shutil
import subprocess
import tempfile
import unittest
from copy import deepcopy
from dataclasses import fields
from pathlib import Path
from unittest.mock import patch

from scripts import size


def instructions(*items: tuple[str, int | None]) -> list[size.Instruction]:
    return [
        size.Instruction(pc, opcode, target)
        for pc, (opcode, target) in enumerate(items, 1)
    ]


def response_for(*code: tuple[str, int | None]) -> dict[str, object]:
    instruction_items = [
        {"pc": pc, "opcode": opcode, **({"target": target} if target else {})}
        for pc, (opcode, target) in enumerate(code, 1)
    ]
    return {
        "runtime": {"version": "LuaJIT", "arch": "x64", "os": "Linux"},
        "vm": {
            "opcode_width": 6,
            "opcode_bits": 8,
            "jump_mode": 13,
            "jump_bias": 0x7FFF,
            "opcodes": sorted(size.KNOWN_OPS),
        },
        "sources": [
            {
                "id": 0,
                "prototypes": [
                    {
                        "info": {
                            "bytecodes": len(code) + 1,
                            "gcconsts": 0,
                            "nconsts": 0,
                            "params": 0,
                            "stackslots": 1,
                            "upvalues": 0,
                            "isvararg": False,
                        },
                        "instructions": instruction_items,
                    }
                ],
            }
        ],
    }


class DiscoveryTests(unittest.TestCase):
    def test_provenance_and_plugin_symlink(self) -> None:
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
            self.assertIn("pack/any-name/start/linked", str(found[1].path))

    def test_cycle_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "pack" / "x" / "start" / "bad").mkdir(parents=True)
            (root / "pack" / "x" / "start" / "bad" / "again").symlink_to(".")
            with self.assertRaisesRegex(size.AnalysisError, "cycle"):
                size.discover(root)

    def test_nested_symlink_escape_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, tempfile.TemporaryDirectory() as external:
            root = Path(temporary)
            plugin = root / "pack" / "x" / "start" / "plugin"
            plugin.mkdir(parents=True)
            escaped = Path(external) / "escaped.lua"
            escaped.write_text("return {}")
            (plugin / "escaped.lua").symlink_to(escaped)
            with self.assertRaisesRegex(size.AnalysisError, "escapes owner root"):
                size.discover(root)

    def test_non_lua_symlink_escapes_are_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, tempfile.TemporaryDirectory() as external:
            root = Path(temporary)
            plugin = root / "pack" / "x" / "start" / "plugin"
            plugin.mkdir(parents=True)
            (plugin / "parser.so").symlink_to("/nix/store/external-parser.so")
            queries = Path(external) / "queries"
            queries.mkdir()
            (queries / "highlights.scm").write_text("(identifier) @variable")
            (plugin / "queries").symlink_to(queries, target_is_directory=True)
            (plugin / "tests").mkdir()
            (plugin / "tests" / "invalid.lua").write_text("local function incomplete(")
            (plugin / "plugin.lua").write_text("return {}")

            found = size.discover(root)

            self.assertEqual([source.path.name for source in found], ["plugin.lua"])


class CfgTests(unittest.TestCase):
    def test_linear_instructions_form_one_basic_block(self) -> None:
        blocks = size.build_cfg(
            instructions(("MOV", None), ("KPRI", None), ("RET0", None))
        )
        self.assertEqual(blocks, [size.Block(1, 3, ())])

    def test_test_and_jump_are_one_decision(self) -> None:
        code = instructions(("ISLT", None), ("JMP", 4), ("KPRI", None), ("RET0", None))
        blocks = size.build_cfg(code)
        self.assertEqual(sum(max(0, len(block.successors) - 1) for block in blocks), 1)
        self.assertTrue(any(block.start == 1 and block.end == 2 for block in blocks))

    def test_key_edge_forms(self) -> None:
        code = instructions(
            ("FORI", 4),
            ("ITERC", None),
            ("ITERL", 2),
            ("ISNEXT", 5),
            ("RET0", None),
        )
        blocks = size.build_cfg(code)
        self.assertEqual(sum(max(0, len(block.successors) - 1) for block in blocks), 2)
        self.assertTrue(any(block.start == 2 and block.end == 3 for block in blocks))

    def test_control_flow_edge_classes(self) -> None:
        cases = {
            "numeric loop": instructions(("FORI", 3), ("RET0", None), ("RET0", None)),
            "iterator pair": instructions(
                ("ITERC", None), ("ITERL", 1), ("RET0", None)
            ),
            "isnext": instructions(("ISNEXT", 3), ("RET0", None), ("RET0", None)),
            "uclose": instructions(("UCLO", 3), ("RET0", None), ("RET0", None)),
            "loop": instructions(("LOOP", 1), ("RET0", None)),
            "return": instructions(("RET", None), ("KPRI", None)),
            "tailcall": instructions(("CALLT", None), ("KPRI", None)),
        }
        expected = {
            "numeric loop": (3, 2),
            "iterator pair": (1, 3),
            "isnext": (3,),
            "uclose": (3,),
            "loop": (),
            "return": (),
            "tailcall": (),
        }
        for name, code in cases.items():
            with self.subTest(name=name):
                first = next(
                    block for block in size.build_cfg(code) if block.start == 1
                )
                self.assertEqual(first.successors, expected[name])

    def test_malformed_control_flow(self) -> None:
        with self.assertRaisesRegex(size.AnalysisError, "not followed"):
            size.build_cfg(instructions(("IST", None), ("RET0", None)))
        with self.assertRaisesRegex(size.AnalysisError, "grouped instruction"):
            size.build_cfg(instructions(("IST", None), ("JMP", 2), ("RET0", None)))
        with self.assertRaisesRegex(size.AnalysisError, "JIT-patched"):
            size.build_cfg(instructions(("JLOOP", 1)))


class MetricAndTreeTests(unittest.TestCase):
    def test_metric_categories(self) -> None:
        code = instructions(
            ("CALL", None),
            ("FNEW", None),
            ("TNEW", None),
            ("TDUP", None),
            ("GGET", None),
            ("GSET", None),
            ("UGET", None),
            ("USETV", None),
            ("RET0", None),
        )
        metrics = size.prototype_metrics(code)
        self.assertEqual(
            (
                metrics.calls,
                metrics.closures,
                metrics.tables,
                metrics.global_reads,
                metrics.global_writes,
                metrics.upvalue_reads,
                metrics.upvalue_writes,
            ),
            (1, 1, 2, 1, 1, 1, 1),
        )

    def test_aggregation_and_collapsing(self) -> None:
        sources = [size.Source(0, ("config", "a", "b", "file.lua"), Path("file.lua"))]
        response = {
            "sources": {
                0: {"prototypes": [{"instructions": instructions(("RET0", None))}]}
            },
        }
        root = size.aggregate(sources, response)
        self.assertEqual(size.assert_aggregation(root).bytecodes, 1)
        config = root.children["config"]
        displayed = list(size._display_children(config, ("config",)))
        self.assertEqual(displayed[0][0], "a/b/file.lua")

        self.assertEqual(len(size._display_rows(root, "bytecodes", 0)), 1)
        self.assertEqual(len(size._display_rows(root, "bytecodes", 1)), 2)

    def test_narrow_render_preserves_paths_values_and_percentages(self) -> None:
        root = size.Node("poincare", total=size.Metrics(bytecodes=123456, decisions=7))
        child = size.Node(
            "a-very-long-logical-directory-name",
            total=size.Metrics(bytecodes=123456, decisions=7),
        )
        root.children["a-very-long-logical-directory-name"] = child
        output = io.StringIO()
        size.render(
            root,
            {"version": "LuaJIT", "arch": "x64", "os": "Linux"},
            1,
            "decisions",
            1,
            file=output,
            width=80,
        )
        rendered = output.getvalue()
        self.assertNotIn("…", rendered)
        self.assertIn("BC=123,456", rendered)
        self.assertIn("parent=100.0%", rendered)
        self.assertIn(
            "poincare/a-very-long-logical-directory-name", rendered.replace("\n", "")
        )

    def test_render_draws_tree_branches_through_detail_lines(self) -> None:
        root = size.Node("poincare", total=size.Metrics(bytecodes=3))
        parent = size.Node(
            "parent",
            own=size.Metrics(bytecodes=1),
            total=size.Metrics(bytecodes=2),
        )
        parent.children["leaf"] = size.Node("leaf", total=size.Metrics(bytecodes=1))
        root.children["parent"] = parent
        root.children["sibling"] = size.Node("sibling", total=size.Metrics(bytecodes=1))
        output = io.StringIO()

        size.render(
            root,
            {"version": "LuaJIT", "arch": "x64", "os": "Linux"},
            2,
            "bytecodes",
            None,
            file=output,
            width=120,
        )

        rendered = output.getvalue()
        self.assertIn("\n├── poincare/parent\n│   BC=2", rendered)
        self.assertIn("\n│   └── poincare/parent/leaf\n│       BC=1", rendered)
        self.assertIn("\n└── poincare/sibling\n    BC=1", rendered)

    def test_zero_denominator_percentage_is_undefined(self) -> None:
        output = io.StringIO()
        size.render(
            size.Node("poincare"),
            {"version": "LuaJIT", "arch": "x64", "os": "Linux"},
            0,
            "global-writes",
            0,
            file=output,
            width=80,
        )
        self.assertIn("parent=n/a  root=n/a", output.getvalue())

    def test_json_contains_complete_uncollapsed_tree(self) -> None:
        root = size.Node(
            "poincare",
            own=size.Metrics(bytecodes=1),
            total=size.Metrics(bytecodes=3, decisions=1),
        )
        root.children["b"] = size.Node(
            "b",
            own=size.Metrics(bytecodes=2, decisions=1),
            total=size.Metrics(bytecodes=2, decisions=1),
        )
        output = io.StringIO()
        response = {
            "runtime": {"version": "LuaJIT", "arch": "x64", "os": "Linux"},
            "vm": {
                "opcode_width": 6,
                "opcode_bits": 8,
                "jump_mode": 13,
                "jump_bias": 0x7FFF,
                "opcodes": sorted(size.KNOWN_OPS),
            },
        }

        size.render_json(root, response, 2, file=output)

        rendered = json.loads(output.getvalue())
        self.assertEqual(
            set(rendered),
            {"format", "runtime", "vm", "source_count", "metrics", "tree"},
        )
        self.assertEqual(rendered["format"], "poincare-size/v1")
        self.assertEqual(rendered["source_count"], 2)
        self.assertEqual(
            rendered["metrics"], [field.name for field in fields(size.Metrics)]
        )
        self.assertEqual(rendered["tree"]["total"]["decisions"], 1)
        self.assertEqual(rendered["tree"]["children"][0]["name"], "b")
        self.assertEqual(rendered["tree"]["children"][0]["own"]["bytecodes"], 2)


class HistoryTests(unittest.TestCase):
    def test_distribution_handles_ties_extremes_and_small_samples(self) -> None:
        self.assertIsNone(size.distribution(10, []))
        self.assertEqual(
            size.distribution(10, [20, 10, 0, 10]),
            {
                "n": 4,
                "percentile": 50,
                "median": 10,
                "q1": 7.5,
                "q3": 12.5,
                "min": 0,
                "max": 20,
            },
        )
        for values in ([10], [10, 10, 10]):
            for current, percentile in ((9, 0), (10, 50), (11, 100)):
                with self.subTest(values=values, current=current):
                    self.assertEqual(
                        size.distribution(current, values),
                        {
                            "n": len(values),
                            "percentile": percentile,
                            "median": 10,
                            "q1": 10,
                            "q3": 10,
                            "min": 10,
                            "max": 10,
                        },
                    )
        self.assertEqual(
            size.distribution(0, [0, 0]),
            {
                "n": 2,
                "percentile": 50,
                "median": 0,
                "q1": 0,
                "q3": 0,
                "min": 0,
                "max": 0,
            },
        )

    def test_local_notes_select_ancestors_and_validate_complete_measurements(
        self,
    ) -> None:
        response = response_for(("RET0", None))
        counts = size.Metrics(bytecodes=10)
        data = size.measurement(
            size.Node("poincare", own=counts, total=counts), response, 1
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)

            def git(*arguments: str, input: str | None = None) -> str:
                return subprocess.run(
                    [
                        "git",
                        "-c",
                        "user.name=Size Test",
                        "-c",
                        "user.email=size@example.invalid",
                        *arguments,
                    ],
                    cwd=root,
                    input=input,
                    text=True,
                    capture_output=True,
                    check=True,
                ).stdout.strip()

            git("init", "--quiet")
            empty_tree = git("mktree", input="")

            def commit(message: str, *parents: str) -> str:
                return git(
                    "commit-tree",
                    empty_tree,
                    *(argument for parent in parents for argument in ("-p", parent)),
                    input=message,
                )

            def annotate(
                revision: str, measurement: object, **metadata: object
            ) -> None:
                note = {
                    "format": "poincare-size-note/v2",
                    "commit": revision,
                    "analyser_commit": revision,
                    "jj_change_id": None,
                    "measurement": measurement,
                    "error": None,
                    **metadata,
                }
                if note["format"] == "poincare-size-note/v1":
                    del note["analyser_commit"]
                    del note["error"]
                git(
                    "notes",
                    f"--ref={size.NOTES_REF}",
                    "add",
                    "--file=-",
                    revision,
                    input=json.dumps(note),
                )

            base = commit("unnoted")
            git("update-ref", "HEAD", base)
            empty = size.load_history(response, root=root)
            self.assertEqual(empty.samples, [])
            self.assertEqual(empty.ancestors, 0)

            first = commit("v2", base)
            annotate(first, data)
            second = commit("v1", first)
            legacy = deepcopy(data)
            legacy["tree"]["own"]["bytecodes"] = 30
            legacy["tree"]["total"]["bytecodes"] = 30
            annotate(second, legacy, format="poincare-size-note/v1")

            invalid = []
            for value in (True, -1, 1.5, "10"):
                bad = deepcopy(data)
                bad["tree"]["own"]["bytecodes"] = value
                invalid.append(bad)
            bad = deepcopy(data)
            bad["tree"]["total"]["bytecodes"] += 1
            invalid.append(bad)
            bad = deepcopy(data)
            del bad["tree"]["own"]["decisions"]
            invalid.append(bad)
            bad = deepcopy(data)
            bad["metrics"] = ["bytecodes"]
            invalid.append(bad)
            bad = deepcopy(data)
            child = size._node_object(size.Node("duplicate"))
            bad["tree"]["children"] = [child, child]
            invalid.append(bad)

            tip = second
            for index, bad in enumerate(invalid):
                tip = commit(f"invalid {index}", tip)
                annotate(tip, bad)
            tip = commit("invalid JSON", tip)
            git("notes", f"--ref={size.NOTES_REF}", "add", "-m", "not JSON", tip)
            tip = commit("wrong attachment", tip)
            annotate(tip, data, commit=first)
            tip = commit("unsupported note", tip)
            annotate(tip, data, format="poincare-size-note/v99")

            for key in ("format", "runtime", "vm"):
                bad = deepcopy(data)
                bad[key] = "different"
                tip = commit(f"incompatible {key}", tip)
                annotate(tip, bad)
            tip = commit("unavailable", tip)
            annotate(tip, None, error="build failed")

            merged = commit("merged side branch", base)
            merged_data = deepcopy(data)
            merged_data["tree"]["own"]["bytecodes"] = 20
            merged_data["tree"]["total"]["bytecodes"] = 20
            annotate(merged, merged_data)
            unrelated = commit("unrelated")
            annotate(unrelated, data)
            head = commit("HEAD", tip, merged)
            annotate(head, data)
            git("update-ref", "HEAD", head)

            history = size.load_history(response, root=root)

        totals = [sample[()].bytecodes for sample in history.samples]
        self.assertEqual(sorted(totals), [10, 20, 30])
        self.assertLess(totals.index(30), totals.index(10))
        self.assertEqual(
            history.skipped,
            {
                "unnoted": 1,
                "unavailable": 1,
                "invalid": len(invalid) + 3,
                "incompatible format/runtime/VM": 3,
            },
        )
        self.assertEqual(
            history.ancestors, len(history.samples) + sum(history.skipped.values())
        )
        self.assertEqual(len(history.warnings), len(invalid) + 3)
        self.assertTrue(any("aggregation" in warning for warning in history.warnings))
        self.assertTrue(any("duplicate" in warning for warning in history.warnings))

    def test_history_render_matches_collapsed_paths_and_historical_shares(self) -> None:
        root = size.Node("poincare", total=size.Metrics(bytecodes=100))
        config = size.Node(
            "config", own=size.Metrics(bytecodes=10), total=size.Metrics(bytecodes=30)
        )
        directory = size.Node("dir", total=size.Metrics(bytecodes=20))
        directory.children["file.lua"] = size.Node(
            "file.lua", total=size.Metrics(bytecodes=20)
        )
        config.children["dir"] = directory
        root.children["config"] = config
        root.children["new.lua"] = size.Node(
            "new.lua", total=size.Metrics(bytecodes=70)
        )
        history = size.History(
            samples=[
                {
                    (): size.Metrics(bytecodes=total),
                    ("config",): size.Metrics(bytecodes=parent),
                    ("config", "dir"): size.Metrics(bytecodes=leaf),
                    ("config", "dir", "file.lua"): size.Metrics(bytecodes=leaf),
                }
                for total, parent, leaf in ((100, 40, 20), (200, 20, 20), (0, 0, 0))
            ]
            + [{(): size.Metrics(bytecodes=100)}],
            ancestors=4,
        )

        for width in (80, 120):
            with self.subTest(width=width):
                output = io.StringIO()
                size.render(
                    root,
                    {"version": "LuaJIT", "arch": "x64", "os": "Linux"},
                    2,
                    "bytecodes",
                    None,
                    all_metrics=True,
                    file=output,
                    width=width,
                    history=history,
                )
                self.assertNotIn("\nCall=", output.getvalue())
                rendered = " ".join(
                    " ".join(
                        line.lstrip("│ ") for line in output.getvalue().splitlines()
                    ).split()
                )
                self.assertIn("poincare/config/dir/file.lua", rendered)
                self.assertIn("BC=20 (P66.7)", rendered)
                self.assertIn("GWrite=0", rendered)
                self.assertNotIn("GWrite=0 (P", rendered)
                self.assertIn("parent=66.7% (P50; 2 samples)", rendered)
                self.assertIn("root=20.0% (P75; 2 samples)", rendered)
                self.assertIn(
                    "BC history (3 of 4 samples): median 20; middle 50% 10-20; range 0-20",
                    rendered,
                )
                self.assertIn("BC history: no earlier samples for this path", rendered)
                self.assertNotIn("…", rendered)

        output = io.StringIO()
        size.render(
            root,
            {"version": "LuaJIT", "arch": "x64", "os": "Linux"},
            2,
            "decisions",
            0,
            file=output,
            width=120,
            history=history,
        )
        self.assertIn("parent=n/a  root=n/a", output.getvalue())
        self.assertIn("Dec history (4 samples): 0 throughout", output.getvalue())

    def test_history_is_explicit_and_does_not_change_snapshot_json(self) -> None:
        self.assertFalse(size.parse_args([]).with_history)
        self.assertTrue(size.parse_args(["--with-history"]).with_history)
        with patch("sys.stderr", new=io.StringIO()), self.assertRaises(SystemExit):
            size.parse_args(["--with-history", "--json"])
        output = io.StringIO()
        size.render(
            size.Node("poincare"),
            {"version": "LuaJIT", "arch": "x64", "os": "Linux"},
            0,
            "bytecodes",
            0,
            file=output,
            width=120,
            history=size.History(),
        )
        self.assertIn("No comparable history", output.getvalue())
        self.assertIn("BC=0", output.getvalue())
        self.assertNotIn("[P", output.getvalue())

    def test_unreadable_history_is_reported(self) -> None:
        with patch(
            "scripts.size.subprocess.run",
            side_effect=[
                subprocess.CompletedProcess([], 0, b"head\nancestor\n", b""),
                subprocess.CompletedProcess([], 0, b"blob ancestor\n", b""),
                subprocess.CompletedProcess([], 128, b"", b"fatal: unreadable note"),
            ],
        ), self.assertRaisesRegex(
            size.AnalysisError, "cannot read size history: fatal: unreadable note"
        ):
            size.load_history(response_for(("RET0", None)))


class GraphTests(unittest.TestCase):
    def test_bar_fills_eighth_cells_and_clamps(self) -> None:
        self.assertEqual(size._bar(0, 4), "    ")
        self.assertEqual(size._bar(1, 4), "████")
        self.assertEqual(size._bar(0.5, 4), "██  ")
        self.assertEqual(size._bar(0.125, 4), "▌   ")
        self.assertEqual(size._bar(2, 2), "██")
        self.assertEqual(size._bar(-1, 2), "  ")
        self.assertEqual(size._bar(0.5, 4, align="right"), "  ██")
        self.assertEqual(size._bar(0.125, 4, align="right"), "   ▌")
        self.assertEqual(size._bar(1, 4, align="right"), "████")

    def test_sparkline_normalises_buckets_and_flat_series(self) -> None:
        self.assertEqual(size._sparkline([], 4), "")
        self.assertEqual(size._sparkline([0, 7], 4), "▁█")
        self.assertEqual(size._sparkline([0, 0, 0], 4), "▁▁▁")
        self.assertEqual(size._sparkline([5, 5, 5], 4), "▄▄▄")
        self.assertEqual(size._sparkline(range(8), 4), "▁▃▆█")
        self.assertEqual(size._sparkline([3, 1, 2], 1), "▄")

    def test_render_to_file_never_emits_graph_glyphs(self) -> None:
        output = io.StringIO()
        size.render(
            size.Node("poincare", total=size.Metrics(bytecodes=2)),
            {"version": "LuaJIT", "arch": "x64", "os": "Linux"},
            1,
            "bytecodes",
            0,
            file=output,
            width=200,
            history=size.History(
                samples=[{(): size.Metrics(bytecodes=1)}], ancestors=1
            ),
        )
        rendered = output.getvalue()
        for glyph in "█▁▂▃▄▅▆▇▏▎▍▌▋▊▉":
            self.assertNotIn(glyph, rendered)


class ProtocolTests(unittest.TestCase):
    def test_runtime_may_omit_known_opcodes(self) -> None:
        source = size.Source(0, ("config", "file.lua"), Path("file.lua"))
        response = response_for(("RET0", None))
        vm = response["vm"]
        self.assertIsInstance(vm, dict)
        assert isinstance(vm, dict)
        vm["opcodes"] = sorted(size.KNOWN_OPS - {"BAND", "BNOT"})

        validated = size.validate_response(response, [source])

        self.assertEqual(validated["sources"][0]["id"], 0)

    def test_source_error_rejects_partial_results(self) -> None:
        sources = [size.Source(0, ("config", "bad.lua"), Path("bad.lua"))]
        response = {
            "runtime": {"version": "LuaJIT", "arch": "x64", "os": "Linux"},
            "vm": {
                "opcode_width": 6,
                "opcode_bits": 8,
                "jump_mode": 13,
                "jump_bias": 0x7FFF,
                "opcodes": sorted(size.KNOWN_OPS),
            },
            "sources": [{"id": 0, "error": "syntax error"}],
        }
        with self.assertRaisesRegex(size.AnalysisError, "Lua compilation failed"):
            size.validate_response(response, sources)

    def test_unknown_opcode_and_target_contracts_are_rejected(self) -> None:
        source = size.Source(0, ("config", "file.lua"), Path("file.lua"))
        cases = {
            "invalid instruction opcode": response_for(("UNKNOWN", None)),
            "must not have": response_for(("MOV", 1)),
            "requires": response_for(("JMP", None)),
        }
        for message, response in cases.items():
            with self.subTest(message=message):
                with self.assertRaisesRegex(size.AnalysisError, message):
                    size.validate_response(response, [source])

    def test_out_of_range_loop_target_is_rejected(self) -> None:
        source = size.Source(0, ("config", "file.lua"), Path("file.lua"))
        with self.assertRaisesRegex(size.AnalysisError, "targets invalid PC 2"):
            size.validate_response(response_for(("LOOP", 2)), [source])

    def test_probe_invokes_neovim_once(self) -> None:
        source = size.Source(0, ("config", "file.lua"), Path("file.lua"))
        result = subprocess.CompletedProcess(
            [], 0, json.dumps(response_for(("RET0", None))), ""
        )
        with patch("scripts.size.subprocess.run", return_value=result) as run:
            size.probe(Path("/nix/store/nvim/bin/nvim"), [source])
        run.assert_called_once()
        command = run.call_args.args[0]
        self.assertEqual(
            command[1:8],
            ["-u", "NONE", "-i", "NONE", "--noplugin", "-n", "-l"],
        )


class IntegrationTests(unittest.TestCase):
    def test_realised_nvim_compiles_without_executing_and_finds_nested_prototypes(
        self,
    ) -> None:
        if shutil.which("nix") is None:
            self.skipTest("nix is unavailable")
        nvim, _ = size.realise_outputs()
        with tempfile.TemporaryDirectory() as temporary:
            source_path = Path(temporary) / "nested.lua"
            source_path.write_text(
                'error("executed")\nlocal function outer(x)\n  if x then\n    return function() return 1 end\n  end\n  return function() return 2 end\nend\nreturn outer\n'
            )
            source = size.Source(0, ("config", "nested.lua"), source_path)
            response = size.probe(nvim, [source])
            self.assertGreaterEqual(len(response["sources"][0]["prototypes"]), 3)
            tree = size.aggregate([source], response)
            self.assertGreaterEqual(tree.total.decisions, 1)


if __name__ == "__main__":
    unittest.main()
