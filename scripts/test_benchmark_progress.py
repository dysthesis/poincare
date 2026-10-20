"""Progress semantics and collector boundaries; real PTY smoke is separate."""

from __future__ import annotations

import importlib.util
import io
import json
import os
import re
import sys
import tempfile
import time
import unittest
from contextlib import ExitStack, contextmanager, redirect_stderr, redirect_stdout
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

try:
    from scripts import benchmark
    from scripts import benchmark_progress as progress
except ModuleNotFoundError:
    import benchmark
    import benchmark_progress as progress


RICH_AVAILABLE = importlib.util.find_spec("rich") is not None


class Terminal(io.StringIO):
    def isatty(self) -> bool:
        return True


def attempt(phase: str = "measure", block: int = 0, **extra: object) -> dict:
    return {
        "phase": phase,
        "block": block,
        "workload": "redraw-control",
        "target": "candidate",
        **extra,
    }


class PlainProgressTests(unittest.TestCase):
    def test_all_attempts_include_warmups_and_failures_without_success_relabeling(
        self,
    ) -> None:
        stream = io.StringIO()
        with progress.BenchmarkProgress(file=stream) as view:
            view.configure(total=3, repeat=2, warmups=1)
            for item, status in (
                (attempt("warmup"), "timeout"),
                (attempt(), "ok"),
                (attempt(block=1), "error"),
            ):
                view.begin(item)
                view.recorded({**item, "status": status, "error": "missing selene"})
            view.finish(complete=True)
        self.assertEqual((view.total, view.completed), (3, 3))
        self.assertEqual((view.successful, view.failed, view.timeouts), (1, 2, 1))
        text = stream.getvalue()
        self.assertIn("Warmup 1/1", text)
        self.assertIn("Run 2/2", text)
        self.assertIn("3/3", text)
        self.assertIn("2 failed", text)
        self.assertIn("1 timed out", text)
        self.assertNotIn("\x1b", text)

    def test_large_redirected_run_has_bounded_logs_but_every_failure(self) -> None:
        stream = io.StringIO()
        schedule = benchmark.make_schedule(["scroll"], ["candidate"], 800, 200, 11)
        with progress.BenchmarkProgress(file=stream) as view:
            view.stage("Preparing fixtures")
            view.configure(total=len(schedule), repeat=800, warmups=200)
            for index, item in enumerate(schedule):
                view.begin(item)
                view.status("Preparing editor")
                view.status("Measuring (display paused)")
                failed = index in (4, 301, 999)
                view.recorded(
                    {
                        **item,
                        "status": "error" if failed else "ok",
                        "error": f"missing tool-{index}" if failed else None,
                    }
                )
            view.stage("Analyzing results")
            view.journal_created(Path("/tmp/benchmark-evidence.jsonl"))
            view.finish(complete=True)
        lines = stream.getvalue().splitlines()
        self.assertLessEqual(len(lines), 20)
        for index in (4, 301, 999):
            self.assertEqual(stream.getvalue().count(f"tool-{index}"), 1)
        self.assertEqual(stream.getvalue().count("/tmp/benchmark-evidence.jsonl"), 1)
        self.assertEqual(view.completed, len(schedule))

    def test_plain_terminal_controls_and_nested_failure_reasons_stay_literal(
        self,
    ) -> None:
        stream = Terminal()
        error = (
            'AcquisitionError: preparation prepared: {"oracle":"prepared",'
            '"error":"required configured executable unavailable: selene [red]"}'
        )
        with progress.BenchmarkProgress(file=stream, plain=True) as view:
            view.configure(total=1, repeat=1, warmups=0)
            view.begin(attempt())
            view.recorded({**attempt(), "status": "error", "error": error})
            view.journal_created(Path("/tmp/evidence\x1b]0;bad\x07\u202e.jsonl"))
            view.finish(complete=True)
        text = stream.getvalue()
        self.assertIn("selene [red]", text)
        self.assertNotIn("oracle", text)
        self.assertNotIn("\x1b", text)
        self.assertNotIn("\u202e", text)
        self.assertIn("\\x1b]0;bad\\x07\\u202e", text)

    def test_repr_escaped_rpc_trace_keeps_long_path_failure_reason_not_stack(
        self,
    ) -> None:
        error = (
            'AcquisitionError: nvim_exec_lua: [0, "Lua: /'
            + "long-project-path/" * 50
            + "benchmark.lua:819: required configured executable unavailable: selene"
            + r"\nstack traceback:\n\t[C]: in function 'assert'\n\tbenchmark.lua:819"
            + '"]'
        )
        summary = progress._error_summary(error)
        self.assertIn("unavailable: selene", summary)
        self.assertNotIn("stack traceback", summary)
        self.assertNotIn("in function", summary)
        self.assertLessEqual(len(summary), 280)
        self.assertNotIn("AcquisitionError", summary)
        self.assertNotIn("nvim_exec_lua", summary)
        self.assertNotIn("long-project-path", summary)
        self.assertNotIn("benchmark.lua:819", summary)

    def test_final_context_preserves_singular_repetition_counts(self) -> None:
        with progress.BenchmarkProgress(file=io.StringIO()) as view:
            view.configure(total=1, repeat=1, warmups=0)
            self.assertRegex(view._context(), r"\b1 measured run\b")
            self.assertNotRegex(view._context(), r"\b1 measured runs\b")
            view.configure(total=2, repeat=1, warmups=1)
            self.assertRegex(view._context(), r"\b1 warmup\b")
            self.assertNotRegex(view._context(), r"\b1 warmups\b")

    def test_progress_disabled_is_silent_even_for_errors_and_journal_path(self) -> None:
        stream = Terminal()
        with patch.object(
            progress.importlib, "import_module", side_effect=AssertionError
        ):
            with progress.BenchmarkProgress(file=stream, enabled=False) as view:
                view.stage("Loading benchmark dependency")
                view.configure(total=1, repeat=1, warmups=0)
                view.begin(attempt())
                view.status("Measuring (display paused)")
                view.recorded({**attempt(), "status": "error", "error": "missing tool"})
                view.journal_created(Path("/tmp/evidence.jsonl"))
                view.finish(complete=True)
        self.assertEqual(stream.getvalue(), "")
        self.assertEqual(view.policy()["mode"], "disabled")

    def test_plain_nonterminal_and_unknown_term_do_not_import_rich(self) -> None:
        for stream, plain, term in (
            (Terminal(), True, "xterm"),
            (io.StringIO(), False, "xterm"),
            (Terminal(), False, "dumb"),
            (Terminal(), False, "unknown"),
        ):
            with self.subTest(plain=plain, term=term, terminal=stream.isatty()):
                with patch.dict(os.environ, {"TERM": term}), patch.object(
                    progress.importlib, "import_module", side_effect=AssertionError
                ):
                    with progress.BenchmarkProgress(file=stream, plain=plain) as view:
                        view.stage("Loading benchmark dependency")
                self.assertEqual(view.mode, "plain")
                self.assertNotIn("\x1b", stream.getvalue())

    def test_missing_optional_rich_falls_back_to_plain(self) -> None:
        stream = Terminal()
        with patch.dict(os.environ, {"TERM": "xterm"}), patch.object(
            progress.importlib, "import_module", side_effect=ImportError("no Rich")
        ):
            with progress.BenchmarkProgress(file=stream) as view:
                view.stage("Preparing fixtures")
                view.configure(total=1, repeat=1, warmups=0)
                view.begin(attempt())
                view.recorded({**attempt(), "status": "ok"})
                view.finish(complete=True)
        self.assertEqual(view.mode, "plain")
        self.assertIn("1/1", stream.getvalue())
        self.assertNotIn("\x1b", stream.getvalue())


@unittest.skipUnless(RICH_AVAILABLE, "optional Rich is not installed")
class RichProgressTests(unittest.TestCase):
    def test_no_workers_or_global_stream_redirects(self) -> None:
        terminal, stdout, stderr = Terminal(), io.StringIO(), io.StringIO()
        with patch.dict(os.environ, {"TERM": "xterm", "COLUMNS": "120"}), patch(
            "threading.Thread.start",
            side_effect=AssertionError("progress started a worker"),
        ), redirect_stdout(stdout), redirect_stderr(stderr):
            with progress.BenchmarkProgress(file=terminal) as view:
                self.assertEqual(view.mode, "rich")
                self.assertIs(sys.stdout, stdout)
                self.assertIs(sys.stderr, stderr)
                view.configure(total=1, repeat=1, warmups=0)
                view.begin(attempt())
                view.status("Measuring (display paused)")
                print("report-only-stdout")
                print("diagnostic-only-stderr", file=sys.stderr)
                view.recorded({**attempt(), "status": "ok"})
                view.finish(complete=True)
        self.assertEqual(stdout.getvalue(), "report-only-stdout\n")
        self.assertEqual(stderr.getvalue(), "diagnostic-only-stderr\n")
        self.assertNotIn("report-only-stdout", terminal.getvalue())
        self.assertIn("\x1b[?25h", terminal.getvalue())

    def test_interruption_restores_cursor_and_reports_only_retained_partial_count(
        self,
    ) -> None:
        for failure in (KeyboardInterrupt(), RuntimeError("fixture failed")):
            with self.subTest(failure=type(failure).__name__):
                terminal = Terminal()
                with patch.dict(os.environ, {"TERM": "xterm", "COLUMNS": "120"}):
                    with self.assertRaises(type(failure)):
                        with progress.BenchmarkProgress(file=terminal) as view:
                            view.configure(total=3, repeat=2, warmups=1)
                            view.journal_created(Path("/tmp/partial.jsonl"))
                            view.begin(attempt("warmup"))
                            view.recorded({**attempt("warmup"), "status": "ok"})
                            view.begin(attempt())
                            raise failure
                text = terminal.getvalue()
                self.assertEqual(view.completed, 1)
                self.assertIn("Stopped", text)
                self.assertNotIn("Finished", text)
                self.assertNotIn("100%", text)
                self.assertEqual(text.count("/tmp/partial.jsonl"), 1)
                self.assertLess(
                    text.rfind("\x1b[?25h"), text.index("/tmp/partial.jsonl")
                )
                self.assertIn("\x1b[?25h", text)

    def test_unknown_duration_stages_have_no_fake_eta(self) -> None:
        now = [100.0]
        with patch.dict(os.environ, {"TERM": "xterm"}), patch.object(
            progress.time, "monotonic", side_effect=lambda: now[0]
        ):
            with progress.BenchmarkProgress(file=Terminal()) as view:

                def rendered_text() -> str:
                    return "".join(
                        segment.text for segment in view._console.render(view._render())
                    )

                view.stage("Resolving and building editor package")
                self.assertNotRegex(rendered_text(), r"remaining:\s*\d")
                view.configure(total=2, repeat=1, warmups=1)
                view.begin(attempt("warmup"))
                now[0] += 10
                view.recorded({**attempt("warmup"), "status": "ok"})
                self.assertRegex(rendered_text(), r"remaining:\s*10s")
                view.stage("Analyzing results and uncertainty")
                self.assertNotRegex(rendered_text(), r"remaining:\s*\d")

    def test_no_color_keeps_textual_state_and_disables_color_sequences(self) -> None:
        terminal = Terminal()
        with patch.dict(os.environ, {"TERM": "xterm-256color", "NO_COLOR": "1"}):
            with progress.BenchmarkProgress(file=terminal) as view:
                view.configure(total=1, repeat=1, warmups=0)
                view.begin(attempt())
                view.recorded(
                    {**attempt(), "status": "error", "error": "missing [red]selene"}
                )
                view.finish(complete=True)
        text = terminal.getvalue()
        self.assertIn("[red]selene", text)
        self.assertIn("1 failed", text)
        for sgr in re.findall(r"\x1b\[([0-9;]*)m", text):
            self.assertFalse(
                any(
                    30 <= int(code) <= 49 or 90 <= int(code) <= 107
                    for code in sgr.split(";")
                    if code
                ),
                f"NO_COLOR output contains a color SGR: {sgr}",
            )


class AcquisitionIsolationTests(unittest.TestCase):
    def test_startup_and_interaction_do_not_write_or_callback_during_scored_interval(
        self,
    ) -> None:
        for startup in (True, False):
            for rich in ((False, True) if RICH_AVAILABLE else (False,)):
                with self.subTest(startup=startup, rich=rich):
                    self.check_boundary(startup=startup, rich=rich)

    def check_boundary(self, *, startup: bool, rich: bool) -> None:
        case = self
        clock = time.perf_counter_ns
        window = {"active": False, "clock_calls": 0}
        activities = []
        surface = {"grids": {"1": ["[No Name] checked screen"]}}

        class GuardedTerminal(Terminal):
            def write(self, text: str) -> int:
                case.assertFalse(
                    window["active"], "terminal write inside scored interval"
                )
                return super().write(text)

        def counter() -> int:
            window["clock_calls"] += 1
            if window["clock_calls"] == 2:
                window["active"] = True
            return clock()

        class Editor:
            def __init__(self, *args: object) -> None:
                self.process = None
                self.screen = SimpleNamespace(snapshot=lambda: surface)
                self.completions = {}
                self.startup_prompt_stopped_ns = None
                case.assertEqual(window["active"], startup)

            def request(self, method: str, *args: object) -> object:
                return [1, {"version": {}}] if method == "nvim_get_api_info" else None

            def lua(self, source: str, *args: object) -> object:
                if source == "return PoincareBenchmark.prepare(...)":
                    return {
                        "steps": [{"kind": "observe", "oracle": "prepared"}],
                        "action": {"kind": "input", "input": "j"},
                        "oracle": "result",
                    }
                if source == "return PoincareBenchmark.runtime()":
                    return {"tools": {}, "path": ""}
                return {}

            def input(self, keys: str) -> None:
                case.assertTrue(window["active"])

            def wait_completion(self, token: str, **kwargs: object) -> dict:
                if token == "measure" or (startup and token == "startup"):
                    case.assertTrue(window["active"])
                    timestamp = clock()
                    window["active"] = False
                else:
                    case.assertFalse(window["active"])
                    timestamp = clock()
                result = {
                    "status": "ok",
                    "oracle": {},
                    "screen": surface,
                    "flush_received_ns": timestamp,
                }
                self.completions[token] = result
                return result

            def close(self) -> dict:
                return {}

        terminal = GuardedTerminal()
        item = attempt(workload="startup-empty" if startup else "redraw-control")
        args = SimpleNamespace(
            state="warm", timeout=1.0, prepare_timeout=1.0, width=80, height=30
        )
        with patch.dict(os.environ, {"TERM": "xterm"}), patch(
            "threading.Thread.start",
            side_effect=AssertionError("progress started a worker"),
        ), patch.object(benchmark, "Nvim", Editor), patch.object(
            benchmark, "isolated_environment", return_value=({}, {})
        ), patch.object(
            benchmark.workloads, "restore_project", return_value="fixed"
        ):
            with progress.BenchmarkProgress(file=terminal, plain=not rich) as view:
                view.configure(total=1, repeat=1, warmups=0)
                view.begin(item)

                def status(activity: str) -> None:
                    self.assertFalse(
                        window["active"], "callback inside scored interval"
                    )
                    activities.append(activity)
                    view.status(activity)

                with patch.object(
                    benchmark.time, "perf_counter_ns", side_effect=counter
                ):
                    result = benchmark.acquire(
                        item,
                        Path("/unused/nvim"),
                        Path("/unused/state"),
                        Path("/unused/project"),
                        {},
                        {"file_facts": {}},
                        args,
                        {},
                        status=status,
                    )
                self.assertEqual(result["status"], "ok", result.get("error"))
                self.assertGreater(result["latency_ns"], 0)
                self.assertFalse(window["active"])
                view.recorded(result)
                view.finish(complete=True)
        self.assertTrue(any("display paused" in activity for activity in activities))
        self.assertTrue(activities)


class CollectorProgressTests(unittest.TestCase):
    def args(self, output: Path, *flags: str):
        return benchmark.parser().parse_args(
            [
                "run",
                "--output",
                str(output),
                "--nvim",
                sys.executable,
                "--workload",
                "redraw-control",
                "--repeat",
                "2",
                "--warmups",
                "1",
                "--resamples",
                "32",
                "--block-length",
                "1",
                "--json",
                "--plain",
                *flags,
            ]
        )

    @contextmanager
    def collection_dependencies(self):
        def acquire(item: dict, *args: object, **kwargs: object) -> dict:
            return {
                "type": "observation",
                **item,
                "status": "ok",
                "latency_ns": 10000 + item["block"],
                "error": None,
            }

        with ExitStack() as stack:
            stack.enter_context(
                patch.dict(
                    sys.modules, {"msgpack": SimpleNamespace(__version__="test")}
                )
            )
            stack.enter_context(patch.object(benchmark, "acquire", side_effect=acquire))
            stack.enter_context(
                patch.object(benchmark, "executable_details", return_value={})
            )
            stack.enter_context(
                patch.object(benchmark.perf, "host_metadata", return_value={})
            )
            yield

    def test_json_stdout_matches_analysis_with_progress_and_no_progress(self) -> None:
        for disabled in (False, True):
            with self.subTest(
                disabled=disabled
            ), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "evidence.jsonl"
                args = self.args(
                    output, *(["--no-progress", "--details"] if disabled else [])
                )
                stderr = io.StringIO()
                case = self

                class ReportOutput(io.StringIO):
                    def write(self, text: str) -> int:
                        if text.strip() and not disabled:
                            case.assertIn("Finished", stderr.getvalue())
                            case.assertIn(str(output), stderr.getvalue())
                        return super().write(text)

                stdout = ReportOutput()
                with self.collection_dependencies(), redirect_stdout(
                    stdout
                ), redirect_stderr(stderr):
                    self.assertEqual(benchmark.run(args), 0)
                records = benchmark._statistics().load_records(output)
                decoded = json.loads(stdout.getvalue())
                self.assertEqual(decoded, benchmark._analyze(records, args))
                self.assertEqual(len(records[1:-1]), 3)
                self.assertEqual(
                    decoded["metadata"]["presentation"]["progress"]["mode"],
                    "disabled" if disabled else "plain",
                )
                self.assertIn("benchmark_progress.py", decoded["metadata"]["harness"])
                if disabled:
                    self.assertEqual(stderr.getvalue(), "")
                else:
                    self.assertIn("3/3", stderr.getvalue())
                    self.assertEqual(stderr.getvalue().count(str(output)), 1)

    def test_fsync_failure_cannot_advance_retained_progress_or_print_stdout(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "partial.jsonl"
            stdout, stderr = io.StringIO(), io.StringIO()
            view = progress.BenchmarkProgress(plain=True, file=stderr)
            original_fsync = os.fsync
            syncs = []

            def fsync(descriptor: int) -> None:
                syncs.append(view.completed)
                if len(syncs) == 3:
                    raise OSError("journal fsync failed")
                original_fsync(descriptor)

            with self.collection_dependencies(), redirect_stdout(
                stdout
            ), redirect_stderr(stderr), patch.object(
                benchmark.benchmark_progress, "BenchmarkProgress", return_value=view
            ), patch.object(
                benchmark.os, "fsync", side_effect=fsync
            ):
                with self.assertRaisesRegex(OSError, "journal fsync failed"):
                    benchmark.run(self.args(output))
            self.assertEqual(syncs, [0, 0, 1])
            self.assertEqual(view.completed, 1)
            self.assertEqual(view.total, 3)
            self.assertEqual(stdout.getvalue(), "")
            self.assertIn("Stopped", stderr.getvalue())
            self.assertNotIn("Finished", stderr.getvalue())
            self.assertEqual(stderr.getvalue().count(str(output)), 1)
            self.assertNotIn('"type":"end"', output.read_text())


if __name__ == "__main__":
    unittest.main()
