from __future__ import annotations

import io
import json
import shutil
import subprocess
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from unittest.mock import patch

from scripts import perf
from scripts import pipeline


def event(identifier: int, parent: int | None, name: str, kind: str, begin: int, end: int) -> dict:
    result = {
        "id": identifier,
        "parent_id": parent,
        "name": name,
        "kind": kind,
        "begin_ns": begin,
        "end_ns": end,
        "duration_ns": end - begin,
        "ok": True,
    }
    if kind == "require":
        result["cached"] = identifier % 2 == 1
        result["module"] = name
    return result


def trace(events: list[dict]) -> str:
    return json.dumps({
        "protocol": "poincare-perf-trace/v1",
        "runtime": {"version": {"major": 0, "minor": 12}, "jit": {"version": "LuaJIT"}},
        "startup_error": None,
        "events": events,
        "steps": [{"name": "run", "ok": True, "error": None}],
        "ok": True,
        "error": None,
        "finished_ns": 1000,
    })


def raw_for(repeat: int = 2, warmups: int = 1) -> dict:
    content = json.dumps({"name": "tiny", "description": "tiny", "steps": [{"name": "run", "lua": "return function() end"}]})
    import hashlib
    digest = hashlib.sha256(content.encode()).hexdigest()
    workload = {"name": "tiny", "path": "tiny.json", "sha256": digest, "content": content, "config": json.loads(content)}
    profile_events = [
        event(1, None, "startup", "startup", 100, 300),
        event(2, 1, "mod", "require", 120, 170),
        event(3, 1, "mod", "require", 180, 200),
        event(4, None, "workload", "workload", 400, 800),
        event(5, 4, "run", "step", 450, 750),
        event(6, 5, "nested", "span", 500, 600),
    ]
    observations = []
    for mode in ("wall", "profile"):
        for iteration in range(warmups + repeat):
            events = profile_events
            if mode == "profile" and iteration == warmups + 1:
                events = [item for item in profile_events if item["name"] != "mod"]
            observations.append({
                "workload": "tiny", "workload_sha256": digest, "mode": mode,
                "iteration": iteration, "warmup": iteration < warmups,
                "started_at_unix_ns": iteration + 1,
                "wall_ns": (10 if mode == "wall" else 1000) + (20 if mode == "wall" and iteration == warmups + 1 else 0),
                "argv": ["nvim"], "cwd": "/tmp", "environment_policy": {"xdg": "isolated"},
                "returncode": 0, "stdout": f"stdout-{iteration}", "stderr": "",
                "timed_out": False, "launch_error": None,
                "trace": trace(events if mode == "profile" else []),
                "trace_read_error": None, "startuptime": "raw profiler text" if mode == "profile" else None,
            })
    schedule = [
        {"workload": "tiny", "mode": mode, "iteration": i, "warmup": i < warmups}
        for mode in ("wall", "profile") for i in range(warmups + repeat)
    ]
    return {
        "format": pipeline.PERF_RAW_FORMAT,
        "workloads": [workload],
        "collection": {"repeat": repeat, "warmups": warmups, "timeout_seconds": 2, "schedule": schedule,
                       "cache_policy": "warm filesystem", "wall_clock_scope": "process"},
        "collector": {"executable": {}, "harness": {"sha256": "1" * 64}, "host": {"os": "test"}},
        "observations": observations,
    }


class ConfigTests(unittest.TestCase):
    def test_defaults_validate_and_selection_is_ordered(self) -> None:
        benches = pipeline.load_benches(pipeline.ROOT / "scripts" / "benches", ["treesitter", "startup"])
        self.assertEqual([bench["name"] for bench in benches], ["treesitter", "startup"])
        self.assertTrue(all(bench["content"] and len(bench["sha256"]) == 64 for bench in benches))

    def test_rejects_unknown_fields_duplicates_bad_names_and_empty_selection(self) -> None:
        cases = [
            ("bad.json", {"name": "bad", "description": "x", "steps": [{"name": "x", "lua": "x"}], "extra": 1}),
            ("bad.json", {"name": "../bad", "description": "x", "steps": [{"name": "x", "lua": "x"}]}),
            ("bad.json", {"name": "bad", "description": "x", "steps": [{"name": "x", "lua": "x"}, {"name": "x", "lua": "y"}]}),
        ]
        for filename, config in cases:
            with self.subTest(config=config), tempfile.TemporaryDirectory() as temporary:
                Path(temporary, filename).write_text(json.dumps(config))
                with self.assertRaises(pipeline.AnalysisError):
                    pipeline.load_benches(Path(temporary))
        with tempfile.TemporaryDirectory() as temporary, self.assertRaisesRegex(pipeline.AnalysisError, "no benches"):
            pipeline.load_benches(Path(temporary))

    def test_cli_numeric_boundaries_reject_bools_by_argparse_shape(self) -> None:
        for arguments in (["--repeat", "0"], ["--warmups", "-1"], ["--timeout", "nan"]):
            with self.subTest(arguments=arguments), patch("sys.stderr", io.StringIO()), self.assertRaises(SystemExit):
                pipeline.parse_perf_args(arguments)


class ProcessingTests(unittest.TestCase):
    def test_nested_repeated_missing_events_and_exact_additive_means(self) -> None:
        raw = raw_for()
        tree, data = pipeline.process_perf_raw(raw)
        tiny = tree.children["tiny"]
        self.assertEqual(tiny.total, {"wall_ns": 20, "profile_ns": 1000})
        self.assertEqual(tiny.children["process-unattributed"].total["profile_ns"], 400)
        self.assertEqual(tiny.children["startup"].children["mod"].total["profile_ns"], 35)
        self.assertEqual(tiny.children["startup"].total["profile_ns"], 200)
        self.assertEqual(data["statistics"]["tiny"]["wall_ns"]["median"], 20)
        self.assertIs(data["raw"], raw)
        self.assertEqual(json.loads(json.dumps(data))["raw"]["observations"][0]["stdout"], "stdout-0")

    def test_single_run_does_not_invent_spread(self) -> None:
        _, data = pipeline.process_perf_raw(raw_for(1, 0))
        stats = data["statistics"]["tiny"]["wall_ns"]
        self.assertIsNone(stats["q1"])
        self.assertIsNone(stats["q3"])
        self.assertIsNone(stats["stddev"])

    def test_additive_tree_uses_mean_not_nonadditive_median(self) -> None:
        raw = raw_for(3, 0)
        values = [1, 2, 100]
        for observation in raw["observations"]:
            if observation["mode"] == "wall":
                observation["wall_ns"] = values[observation["iteration"]]
        tree, data = pipeline.process_perf_raw(raw)
        self.assertAlmostEqual(tree.children["tiny"].total["wall_ns"], 103 / 3)
        self.assertEqual(data["statistics"]["tiny"]["wall_ns"]["median"], 2)

    def test_invalid_failure_overlap_negative_nonfinite_and_incomplete_are_rejected(self) -> None:
        cases = []
        failed = raw_for(); failed["observations"][0]["returncode"] = 1; cases.append(failed)
        incomplete = raw_for(); incomplete["observations"].pop(); cases.append(incomplete)
        negative = raw_for(); negative["observations"][0]["wall_ns"] = -1; cases.append(negative)
        nonfinite = raw_for(); nonfinite["observations"][0]["wall_ns"] = float("inf"); cases.append(nonfinite)
        overlap = raw_for(); profile = next(o for o in overlap["observations"] if o["mode"] == "profile")
        payload = json.loads(profile["trace"]); payload["events"][2]["begin_ns"] = 160; payload["events"][2]["duration_ns"] = 40; profile["trace"] = json.dumps(payload); cases.append(overlap)
        for broken in cases:
            with self.subTest(case=cases.index(broken)), self.assertRaises(pipeline.AnalysisError):
                pipeline.process_perf_raw(broken)

    def test_raw_replay_never_invokes_collector(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary, "raw.json"); path.write_text(json.dumps(raw_for(1, 0)))
            output = io.StringIO()
            with patch("scripts.perf.collect", side_effect=AssertionError), patch("sys.stdout", output):
                self.assertEqual(pipeline.perf_main(["--input", str(path), "--json"]), 0)
        self.assertEqual(json.loads(output.getvalue())["format"], pipeline.PERF_OUTPUT_FORMAT)


class CollectorTests(unittest.TestCase):
    def test_attempt_preserves_warmup_output_and_launch_failure(self) -> None:
        workload = pipeline.load_benches(pipeline.ROOT / "scripts" / "benches", ["startup"])[0]
        with patch("subprocess.Popen", side_effect=OSError("missing")):
            observation = perf.run_attempt(Path("/missing/nvim"), workload, "wall", 3, True, 1)
        self.assertTrue(observation["warmup"])
        self.assertEqual(observation["iteration"], 3)
        self.assertIn("missing", observation["launch_error"])
        self.assertIsNone(observation["returncode"])
        self.assertIn("stdout", observation)

    def test_timeout_kills_process_group_and_preserves_partial_output(self) -> None:
        workload = pipeline.load_benches(pipeline.ROOT / "scripts" / "benches", ["startup"])[0]

        class Process:
            pid = 42
            returncode = -9
            calls = 0

            def communicate(self, timeout=None):
                self.calls += 1
                if self.calls == 1:
                    raise subprocess.TimeoutExpired(["nvim"], timeout or 0)
                return "partial stdout", "partial stderr"

        with patch("subprocess.Popen", return_value=Process()), patch("os.killpg") as kill:
            observation = perf.run_attempt(Path("/nvim"), workload, "wall", 0, False, 0.01)
        kill.assert_called_once_with(42, 9)
        self.assertTrue(observation["timed_out"])
        self.assertEqual(observation["stdout"], "partial stdout")
        self.assertEqual(observation["stderr"], "partial stderr")


class HistoryTests(unittest.TestCase):
    def test_perf_history_accepts_float_roundoff_and_skips_incompatible_protocol(self) -> None:
        _, current = pipeline.process_perf_raw(raw_for(1, 0))
        compatible = deepcopy(current)
        compatible["tree"]["total"]["profile_ns"] += 1e-7
        incompatible = deepcopy(current)
        incompatible["compatibility"]["protocol"] = "different"
        notes = {
            "a": json.dumps({"format": "poincare-perf-note/v1", "commit": "a", "measurement": compatible, "error": None}).encode(),
            "b": json.dumps({"format": "poincare-perf-note/v1", "commit": "b", "measurement": incompatible, "error": None}).encode(),
        }

        def run(argv, **kwargs):
            if "rev-list" in argv:
                output = b"head\na\nb\n"
            elif "list" in argv:
                output = b"blob-a a\nblob-b b\n"
            else:
                output = notes["a" if argv[-1] == "blob-a" else "b"]
            return subprocess.CompletedProcess(argv, 0, output, b"")

        with patch("subprocess.run", side_effect=run):
            history = pipeline.load_history(current, kind=pipeline.PERF_KIND)
        self.assertEqual(len(history.samples), 1, history.warnings)
        self.assertEqual(history.skipped["incompatible format/runtime/VM"], 1)


class IntegrationTests(unittest.TestCase):
    def test_realised_completion_smoke_preserves_and_decomposes_trace(self) -> None:
        if shutil.which("nix") is None:
            self.skipTest("nix is unavailable")
        nvim, _ = pipeline.realise_outputs(pipeline.ROOT)
        workloads = pipeline.load_benches(pipeline.ROOT / "scripts" / "benches")
        raw = perf.collect(nvim, workloads, repeat=2, warmups=1, timeout=30)
        tree, data = pipeline.process_perf_raw(raw)
        self.assertEqual(len(raw["observations"]), 24)
        self.assertEqual(tree.children["completion"].total["profile_ns"], data["statistics"]["completion"]["profile_ns"]["mean"])
        profile_trace = json.loads(next(item["trace"] for item in raw["observations"] if item["workload"] == "completion" and item["mode"] == "profile"))
        self.assertTrue(any(item["kind"] == "require" for item in profile_trace["events"]))
        self.assertEqual(json.loads(json.dumps(data))["raw"]["format"], pipeline.PERF_RAW_FORMAT)


if __name__ == "__main__":
    unittest.main()
