"""Boundary tests; real packaged-editor scenario smoke belongs to integration."""

from __future__ import annotations

import argparse
import json
import os
import select
import signal
import subprocess
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path
from unittest.mock import Mock, patch

try:
    from scripts import benchmark
    from scripts import benchmark_rpc as rpc
    from scripts import benchmark_workloads as workloads
except ModuleNotFoundError:
    import benchmark
    import benchmark_rpc as rpc
    import benchmark_workloads as workloads


class CausalFlushTests(unittest.TestCase):
    def client(self) -> rpc.Nvim:
        # Test only the wire-event state machine, not a replacement editor.
        client = rpc.Nvim.__new__(rpc.Nvim)
        client.screen = rpc.Screen()
        client.completions = {}
        client.responses = {}
        client.notifications = []
        client.next_id = 1
        client.operation_deadline = None
        client.startup_prompt_handling = True
        client.startup_prompt_acknowledgements = []
        client.startup_prompt_stopped_ns = None
        client._startup_mode_request = None
        client._startup_input_request = None
        client._startup_return_latched = False
        client._startup_last_prompt = None
        client.startup_last_mode = None
        client.send = Mock()
        return client

    def redraw(self, client: rpc.Nvim, timestamp: int, *events: list) -> None:
        client._dispatch([2, "redraw", list(events)], timestamp)

    def test_only_flush_after_oracle_qualifies_and_freezes_surface(self) -> None:
        client = self.client()
        self.redraw(
            client,
            10,
            ["grid_resize", [1, 5, 1]],
            ["grid_line", [1, 0, 0, [["o", 1], ["l"], ["d"]]]],
            ["flush", []],
        )
        client._dispatch(
            [2, "poincare_benchmark", ["sample", "ok", {"success": True}]], 20
        )
        self.assertIsNone(client.completions["sample"]["flush_received_ns"])
        self.redraw(
            client,
            30,
            ["grid_line", [1, 0, 0, [["n", 2], ["e"], ["w"]]]],
            ["flush", []],
        )
        completed = client.completions["sample"]
        self.assertEqual(completed["flush_received_ns"], 30)
        self.assertTrue(completed["screen"]["grids"]["1"][0].startswith("new"))
        self.redraw(
            client,
            40,
            ["grid_line", [1, 0, 0, [["l", 3], ["a"], ["t"], ["e"], ["r"]]]],
            ["flush", []],
        )
        self.assertTrue(completed["screen"]["grids"]["1"][0].startswith("new"))
        self.assertEqual(completed["screen"]["highlight_ids"]["1"][0][0], 2)
        self.assertEqual(completed["flush_received_ns"], 30)

    def test_oracle_without_flush_is_not_completed(self) -> None:
        client = self.client()
        client._dispatch(
            [2, "poincare_benchmark", ["sample", "timeout", {"success": False}]], 20
        )
        self.redraw(client, 30, ["grid_resize", [1, 5, 1]])
        self.assertIsNone(client.completions["sample"]["flush_received_ns"])

    def test_highlighted_endpoint_waits_for_syntax_colors_after_file_ready(
        self,
    ) -> None:
        client = self.client()
        probes = [
            {"grid": 1, "row": 0, "column": 0, "text": "def", "foreground": 0x112233},
            {
                "grid": 1,
                "row": 0,
                "column": 4,
                "text": "sample",
                "foreground": 0x445566,
            },
        ]
        self.redraw(
            client,
            10,
            ["grid_resize", [1, 10, 1]],
            ["hl_attr_define", [7, {"foreground": 0xAAAAAA}, {}, []]],
            ["hl_attr_define", [8, {"foreground": 0x112233}, {}, []]],
            ["hl_attr_define", [9, {"foreground": 0x445566}, {}, []]],
            ["grid_line", [1, 0, 0, [[c, 7] for c in "def sample"]]],
            ["flush", []],
        )
        client._dispatch(
            [
                2,
                "poincare_benchmark",
                ["measure", "ok", {"required_highlights": probes}],
            ],
            20,
        )
        self.redraw(client, 30, ["flush", []])
        self.assertIsNone(client.completions["measure"]["flush_received_ns"])
        self.redraw(
            client,
            40,
            ["grid_line", [1, 0, 0, [[c, 8] for c in "def"]]],
            ["flush", []],
        )
        self.assertIsNone(client.completions["measure"]["flush_received_ns"])
        self.redraw(
            client,
            45,
            ["grid_line", [1, 0, 4, [[c, 9] for c in "sample"]]],
        )
        self.assertIsNone(client.completions["measure"]["flush_received_ns"])
        self.redraw(client, 50, ["flush", []])
        completed = client.completions["measure"]
        self.assertEqual(completed["flush_received_ns"], 50)
        self.redraw(
            client,
            60,
            ["hl_attr_define", [9, {"foreground": 0xAABBCC}, {}, []]],
            ["grid_clear", [1]],
            ["flush", []],
        )
        self.assertEqual(completed["screen"]["grids"]["1"], ["def sample"])
        self.assertEqual(
            completed["screen"]["highlight_definitions"][9]["foreground"], 0x445566
        )

    def test_highlight_color_alone_cannot_match_the_wrong_text_or_position(
        self,
    ) -> None:
        screen = rpc.Screen()
        screen.apply("grid_resize", [1, 4, 2])
        screen.apply("hl_attr_define", [1, {"foreground": 0x123456}, {}, []])
        screen.apply("grid_line", [1, 1, 0, [[c, 1] for c in "def "]])
        probe = {
            "grid": 1,
            "row": 0,
            "column": 0,
            "text": "def",
            "foreground": 0x123456,
        }
        self.assertFalse(screen.has_highlights([probe]))
        screen.apply("grid_line", [1, 0, 0, [[c, 1] for c in "xyz "]])
        self.assertFalse(screen.has_highlights([probe]))
        screen.apply("grid_line", [1, 0, 0, [[c, 1] for c in "def "]])
        self.assertTrue(screen.has_highlights([probe]))

    def test_failed_highlight_oracle_does_not_wait_for_missing_syntax(self) -> None:
        client = self.client()
        client._dispatch(
            [
                2,
                "poincare_benchmark",
                [
                    "measure",
                    "error",
                    {
                        "required_highlights": [
                            {
                                "grid": 1,
                                "row": 0,
                                "column": 0,
                                "text": "def",
                                "foreground": 0x123456,
                            }
                        ],
                    },
                ],
            ],
            10,
        )
        self.redraw(client, 20, ["grid_resize", [1, 3, 1]], ["flush", []])
        self.assertEqual(client.completions["measure"]["status"], "error")
        self.assertEqual(client.completions["measure"]["flush_received_ns"], 20)

    def test_nonqualifying_flushes_do_not_extend_the_operation_deadline(self) -> None:
        client = self.client()
        client.timeout = 30
        client.operation_deadline = 3
        client.startup_prompt_handling = False
        probe = {"grid": 1, "row": 0, "column": 0, "text": "def", "foreground": 1}
        self.redraw(client, 0, ["grid_resize", [1, 3, 1]])
        client._dispatch(
            [
                2,
                "poincare_benchmark",
                ["measure", "ok", {"required_highlights": [probe]}],
            ],
            0,
        )
        now = 0
        deadlines = []

        def pending_flush(deadline):
            nonlocal now
            now += 1
            deadlines.append(deadline)
            if now >= client.operation_deadline:
                # Exercise the real pump's expiration path, not a mock timeout.
                return rpc.Nvim.pump(client, deadline)
            self.redraw(
                client,
                now,
                ["grid_line", [1, 0, 0, [[c, 0] for c in "def"]]],
                ["flush", []],
            )

        client.pump = pending_flush
        with patch.object(rpc.time, "monotonic", side_effect=lambda: now):
            with self.assertRaises(rpc.AcquisitionTimeout):
                client.wait_completion("measure")
        self.assertEqual(deadlines, [3, 3, 3])
        self.assertIsNone(client.completions["measure"]["flush_received_ns"])

    def test_partial_user_input_fails_without_retry(self) -> None:
        client = self.client()
        client.request = Mock(return_value=2)
        with self.assertRaisesRegex(rpc.AcquisitionError, "no automatic input retry"):
            client.input("abcdef")
        client.request.assert_called_once_with("nvim_input", "abcdef")

    def test_startup_acknowledges_only_actual_return_mode_once(self) -> None:
        client = self.client()
        for mode in ("n", "rm", "r?", "c"):
            client._startup_mode_response({"mode": mode, "blocking": True}, 10)
        client.send.assert_not_called()
        client._startup_mode_response({"mode": "r", "blocking": True}, 20)
        client.send.assert_called_once_with([0, 1, "nvim_input", ["<CR>"]], None)
        client._startup_mode_response({"mode": "r", "blocking": True}, 21)
        self.assertEqual(len(client.startup_prompt_acknowledgements), 1)
        self.assertEqual(
            client.startup_prompt_acknowledgements[0]["detected_at_perf_ns"], 20
        )

    def test_startup_readiness_disables_later_prompt_acknowledgement(self) -> None:
        client = self.client()
        client._dispatch(
            [2, "poincare_benchmark", ["startup", "ok", {"success": True}]], 30
        )
        client._startup_mode_response({"mode": "r", "blocking": True}, 40)
        client.send.assert_not_called()
        self.assertFalse(client.startup_prompt_handling)
        self.assertEqual(client.startup_prompt_stopped_ns, 30)


@unittest.skipUnless(
    os.name == "posix" and hasattr(os, "pidfd_open"),
    "requires Linux process-group/pidfd support",
)
class CleanupTests(unittest.TestCase):
    def test_root_exit_does_not_leave_a_real_child_process_alive(self) -> None:
        child_code = (
            "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); "
            "print('ready',flush=True); time.sleep(60)"
        )
        parent_code = (
            "import subprocess,sys; "
            f"child=subprocess.Popen([sys.executable,'-c',{child_code!r}],"
            "stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL); "
            "assert child.stdout.readline()==b'ready\\n'; "
            "print(child.pid,flush=True)"
        )
        process = subprocess.Popen(
            [sys.executable, "-c", parent_code],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        descriptor = None
        try:
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, stderr.decode(errors="replace"))
            descriptor = os.pidfd_open(int(stdout.strip()))
            self.assertFalse(
                select.select([descriptor], [], [], 0)[0],
                "child must be alive before cleanup",
            )
            result = rpc.kill_process_group(process, grace=0.05)
            self.assertTrue(
                select.select([descriptor], [], [], 5)[0],
                "cleanup left the child alive after its parent exited",
            )
            self.assertEqual(result["returncode_before_cleanup"], 0)
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            if descriptor is not None:
                os.close(descriptor)
            process.wait(timeout=5)
            for pipe in (process.stdout, process.stderr):
                if pipe is not None:
                    pipe.close()


class ScheduleAndEvidenceTests(unittest.TestCase):
    def test_every_phase_is_balanced_adjacent_complete_pairs(self) -> None:
        names = ["startup-empty", "scroll", "picker-files-first"]
        schedule = benchmark.make_schedule(names, ["baseline", "candidate"], 7, 3, 29)
        self.assertEqual(
            schedule,
            benchmark.make_schedule(names, ["baseline", "candidate"], 7, 3, 29),
        )
        for phase, count in (("warmup", 3), ("measure", 7)):
            rows = [row for row in schedule if row["phase"] == phase]
            self.assertEqual(len(rows), count * len(names) * 2)
            firsts = {name: Counter() for name in names}
            for index in range(0, len(rows), 2):
                first, second = rows[index : index + 2]
                self.assertEqual(first["workload"], second["workload"])
                self.assertEqual(first["block"], second["block"])
                self.assertEqual(
                    {first["target"], second["target"]}, {"baseline", "candidate"}
                )
                firsts[first["workload"]][first["target"]] += 1
            for name in names:
                self.assertLessEqual(
                    abs(firsts[name]["baseline"] - firsts[name]["candidate"]), 1
                )
                for block in range(count):
                    self.assertEqual(
                        sum(
                            row["workload"] == name and row["block"] == block
                            for row in rows
                        ),
                        2,
                    )

    def test_isolation_removes_user_overrides_without_selecting_appname(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            inherited = {
                "HOME": "/user",
                "NVIM_APPNAME": "user",
                "VIMINIT": "bad",
                "LUA_INIT_5_1": "bad",
                "GIT_DIR": "/user/repo",
                "TMUX": "user",
                "DISPLAY": ":0",
                "PATH": "/bin",
            }
            with patch.dict(os.environ, inherited, clear=True):
                environment, policy = benchmark.isolated_environment(
                    Path(directory) / "isolated"
                )
            for key in (
                "NVIM_APPNAME",
                "VIMINIT",
                "LUA_INIT_5_1",
                "GIT_DIR",
                "TMUX",
                "DISPLAY",
            ):
                self.assertNotIn(key, environment)
            self.assertNotEqual(environment["HOME"], "/user")
            self.assertTrue(Path(environment["HOME"]).is_dir())
            self.assertEqual(environment["PATH"], "/bin")
            self.assertEqual(policy["git_user_system_config"], "disabled")

    def test_error_observation_survives_incremental_jsonl_write(self) -> None:
        observation = {
            "type": "observation",
            "phase": "measure",
            "block": 0,
            "workload": "scroll",
            "target": "candidate",
            "status": "timeout",
            "latency_ns": None,
            "error": "oracle expired",
            "stderr": "retained evidence",
            "screen": {"rows": ["partial UI"]},
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "evidence.jsonl"
            with path.open("w", encoding="utf-8") as stream:
                benchmark._append_journal(stream, observation)
                self.assertEqual(json.loads(path.read_text()), observation)
        with self.assertRaisesRegex(ValueError, "nonfinite"):
            benchmark._json_safe({"latency_ns": float("nan")})

    def test_fixture_failure_is_an_error_observation_not_a_missing_sample(self) -> None:
        item = {
            "phase": "measure",
            "block": 0,
            "workload": "startup-empty",
            "target": "candidate",
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(
                workloads,
                "restore_project",
                side_effect=RuntimeError("git fixture prerequisite failed"),
            ), patch.object(benchmark, "Nvim") as spawn:
                result = benchmark.acquire(
                    item,
                    Path("/unused/nvim"),
                    root / "state",
                    root / "project",
                    {},
                    {},
                    argparse.Namespace(state="warm"),
                    {},
                )
        self.assertEqual(result["status"], "error")
        self.assertIsNone(result["latency_ns"])
        self.assertIn("git fixture prerequisite failed", result["error"])
        self.assertEqual({key: result[key] for key in item}, item)
        spawn.assert_not_called()

    def test_catalog_explicit_selection_does_not_include_implicit_core(self) -> None:
        self.assertEqual(
            [
                item.name
                for item in workloads.select_workloads(None, ["redraw-control"])
            ],
            ["redraw-control"],
        )
        self.assertNotIn(
            "redraw-control",
            [item.name for item in workloads.select_workloads(None, None)],
        )


class ObserverAndReplayBoundaryTests(unittest.TestCase):
    def test_large_open_payload_contains_facts_not_the_source_corpus(self) -> None:
        files = workloads.corpus_files()
        config = workloads.scenario_config(
            workloads.BY_NAME["open-large"], files, workloads.corpus_file_facts(files)
        )
        self.assertEqual(set(config["file_facts"]), {"python/large.py"})
        self.assertLess(len(json.dumps(config).encode()), 2048)

    def records(self) -> list[dict]:
        schedule = benchmark.make_schedule(["redraw-control"], ["candidate"], 2, 0, 11)
        manifest = {
            "type": "manifest",
            "format": benchmark.FORMAT,
            "seed": 11,
            "repeat": 2,
            "warmups": 0,
            "targets": ["candidate"],
            "workloads": [{"name": "redraw-control"}],
            "schedule": schedule,
            "metadata": {
                "analysis_plan": {
                    "resamples": 64,
                    "confidence": 0.9,
                    "practical": 0.1,
                    "seed": 53,
                    "block_length": 1,
                }
            },
        }
        observations = [
            {
                "type": "observation",
                **item,
                "status": "ok",
                "latency_ns": 10000 + index * 100,
                "error": None,
            }
            for index, item in enumerate(schedule)
        ]
        return [manifest, *observations, {"type": "end", "complete": True}]

    def test_report_replays_the_recorded_plan_without_implicit_overrides(self) -> None:
        records = self.records()
        args = benchmark.parser().parse_args(["report", "unused.jsonl"])
        report = benchmark._analyze(records, args)
        self.assertEqual(
            report["analysis_overrides"]["effective_plan"],
            records[0]["metadata"]["analysis_plan"],
        )
        self.assertEqual(report["analysis_overrides"]["overrides"], {})
        self.assertEqual(report["statistics"]["seed"], 53)

    def test_explicit_report_flags_are_sensitivity_overrides_even_if_equal(
        self,
    ) -> None:
        records = self.records()
        args = benchmark.parser().parse_args(
            ["report", "unused.jsonl", "--resamples", "32", "--confidence", "0.9"]
        )
        report = benchmark._analyze(records, args)
        self.assertEqual(
            report["analysis_overrides"]["overrides"],
            {"resamples": 32, "confidence": 0.9},
        )
        self.assertEqual(report["statistics"]["resamples"], 32)
        self.assertEqual(report["analysis_overrides"]["stored_plan"]["resamples"], 64)

    def test_malformed_recorded_plan_has_a_public_data_error(self) -> None:
        records = self.records()
        records[0]["metadata"]["analysis_plan"] = ["not", "an", "object"]
        args = benchmark.parser().parse_args(["report", "unused.jsonl"])
        with self.assertRaisesRegex(ValueError, "analysis_plan"):
            benchmark._analyze(records, args)


if __name__ == "__main__":
    unittest.main()
