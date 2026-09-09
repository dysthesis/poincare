from __future__ import annotations

import io
import json
import shutil
import subprocess
import tempfile
import unittest
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


class ProtocolTests(unittest.TestCase):
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
