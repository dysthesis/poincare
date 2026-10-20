from __future__ import annotations

import builtins
import importlib.util
import io
import os
import re
import unittest
import unicodedata
from copy import deepcopy
from unittest.mock import patch

from scripts.benchmark_display import print_report
from scripts.benchmark_stats import analyze
from scripts.test_benchmark_stats import MS, fail, journal, measured


class Terminal(io.StringIO):
    def isatty(self) -> bool:
        return True


def numbers(text: str) -> list[float]:
    return [
        float(value)
        for value in re.findall(
            r"(?<![\w.])[-+]?\d+(?:\.\d+)?(?:e[-+]?\d+)?",
            text,
            re.IGNORECASE,
        )
    ]


def report(
    candidate: list[int], baseline: list[int] | None = None, **options: object
) -> dict:
    return analyze(
        journal(candidate, baseline), resamples=2048, block_length=1, **options
    )


class ReportCases:
    plain = True

    def render(self, data: dict, *, width: int = 120, details: bool = False) -> str:
        stream = io.StringIO() if self.plain else Terminal()
        with patch.dict(os.environ, {"TERM": "xterm-256color", "NO_COLOR": "1"}):
            print_report(
                data, plain=self.plain, details=details, file=stream, width=width
            )
        return stream.getvalue()

    def test_paired_change_and_interval_are_not_a_ratio_of_medians(self) -> None:
        data = report(
            [value * MS for value in [50, 100, 200, 400] * 5], [100 * MS] * 20
        )
        workload = data["workloads"][0]
        comparison = workload["comparison"]
        medians = [
            target["descriptive"]["median_ns"]
            for target in workload["targets"].values()
        ]
        self.assertNotAlmostEqual(
            comparison["percent_change"], (medians[1] / medians[0] - 1) * 100
        )
        for width in (48, 80, 120):
            with self.subTest(width=width):
                text = self.render(data, width=width)
                values = numbers(text)
                self.assertIn(float(f"{comparison['percent_change']:.3g}"), values)
                for endpoint in comparison["ratio_ci"]:
                    self.assertIn(float(f"{(endpoint - 1) * 100:.3g}"), values)
                self.assertIn("%", text)
                self.assertIn("ms", text)
                self.assertIn("paired", text.lower())

    def test_single_target_median_ci_p95_and_success_counts_have_units(self) -> None:
        data = report([value * 1000 for value in range(1100, 1300, 10)])
        target = data["workloads"][0]["targets"]["candidate"]
        for width in (48, 120):
            with self.subTest(width=width):
                text = self.render(data, width=width)
                values = numbers(text)
                expected = [
                    target["descriptive"]["median_ns"],
                    target["descriptive"]["p95_ns"],
                    *target["median_ci_ns"],
                ]
                for value in expected:
                    self.assertIn(float(f"{value / MS:.4g}"), values)
                self.assertIn("ms", text)
                self.assertIn("20/20", text)
                self.assertIn("*", text)
                self.assertIn("p95", text)
                self.assertNotRegex(text.lower(), r"baseline|regression|faster|slower")

    def test_shared_latency_unit_changes_with_scale(self) -> None:
        for latency, unit, displayed in (
            (5000, "µs", 5),
            (1_250_000, "ms", 1.25),
            (2_500_000_000, "s", 2.5),
        ):
            with self.subTest(unit=unit):
                text = self.render(report([latency] * 20), width=80)
                self.assertIn(f"({unit})", text)
                self.assertIn(displayed, numbers(text))
                self.assertNotIn(str(latency), text)

    def test_verdicts_follow_engine_decisions_including_uncertainty(self) -> None:
        cases = [
            (
                report([120 * MS] * 20, [100 * MS] * 20),
                "regression",
                r"slower|regression",
            ),
            (
                report([80 * MS] * 20, [100 * MS] * 20),
                "improvement",
                r"faster|improvement",
            ),
            (
                report([102 * MS] * 20, [100 * MS] * 20),
                "within practical band",
                r"within|about same",
            ),
            (
                report([50 * MS, 200 * MS] * 15, [100 * MS] * 30),
                "inconclusive",
                r"uncertain|inconclusive",
            ),
        ]
        for data, decision, meaning in cases:
            with self.subTest(decision=decision):
                self.assertEqual(data["workloads"][0]["decision"], decision)
                text = self.render(data).lower()
                self.assertRegex(text, meaning)
                self.assertNotIn("no regression", text)
                if decision == "within practical band":
                    self.assertIn("±5%", text)
                elif decision == "inconclusive":
                    self.assertNotRegex(text, r"within ±|about same")

    def test_exploratory_warnings_distinguish_more_runs_from_more_resamples(
        self,
    ) -> None:
        underresolved = analyze(
            journal([120 * MS] * 30, [100 * MS] * 30), resamples=1, block_length=1
        )
        few = report([120 * MS] * 19, [100 * MS] * 19)
        degenerate = analyze(
            journal([120 * MS] * 20, [100 * MS] * 20), resamples=2048, block_length=20
        )
        for data in (underresolved, few, degenerate):
            self.assertEqual(data["workloads"][0]["decision"], "exploratory")
            self.assertRegex(
                self.render(data).lower(), r"not enough evidence|exploratory"
            )
        text = self.render(underresolved).lower()
        self.assertIn("bootstrap", text)
        self.assertIn("--resamples", text)
        self.assertNotIn("--repeat", text)
        self.assertIn("--repeat", self.render(few))
        text = self.render(degenerate)
        self.assertIn("--block-length", text)
        self.assertIn("--resamples", text)
        self.assertRegex(text.lower(), r"no uncertainty|unavailable")

    def test_single_counts_and_unavailable_intervals_keep_their_meaning(self) -> None:
        records = journal([MS], warmups=1)
        data = analyze(records, resamples=2048, block_length=1)
        self.assertFalse(data["statistics"]["intervals_available"])
        text = " ".join(self.render(data, width=80).split()).lower()
        for label in ("run", "warmup", "workload"):
            self.assertRegex(text, rf"\b1 {label}\b")
            self.assertNotRegex(text, rf"\b1 {label}s\b")
        self.assertNotIn("exploratory", text)
        self.assertRegex(text, r"no uncertainty|unavailable")
        self.assertIn("--details", text)

        fail(measured(records), "error")
        failed = analyze(records, resamples=2048, block_length=1)
        text = " ".join(self.render(failed, width=80).split()).lower()
        self.assertRegex(text, r"\b1 failed observation\b")
        self.assertNotRegex(text, r"\b1 failed observations\b")

    def test_warmup_failure_is_failed_even_with_complete_measured_counts(self) -> None:
        for paired in (False, True):
            with self.subTest(paired=paired):
                records = journal([12_340_000] * 20, [10 * MS] * 20 if paired else None)
                failure = next(
                    row
                    for row in records[1:-1]
                    if row["phase"] == "warmup" and row["target"] == "candidate"
                )
                fail(failure, "timeout")
                data = analyze(records, resamples=2048, block_length=1)
                text = self.render(data)
                self.assertRegex(text.lower(), r"failed|failure")
                self.assertIn("warmup", text)
                self.assertIn("candidate", text)
                self.assertNotIn("12.34", text)
                self.assertRegex(text.lower(), r"unavailable|n/a")
                if not paired:
                    self.assertIn("20/20", text)
                self.assertIn("12.34", self.render(data, details=True))

    def test_no_successful_measurements_are_never_zero_fast(self) -> None:
        records = journal([MS] * 20, warmups=0)
        for row in records[1:-1]:
            fail(row, "timeout")
        text = self.render(analyze(records, resamples=2048, block_length=1))
        self.assertIn("0/20", text)
        self.assertRegex(text.lower(), r"failed|failure")
        self.assertRegex(text.lower(), r"unavailable|n/a")
        self.assertNotRegex(text, r"\b0(?:\.0+)?\s+(?:ns|µs|ms|s)\b")

    def test_failure_summary_preserves_missing_tool_reason_and_full_details(
        self,
    ) -> None:
        records = journal([MS] * 20)
        failure = measured(records)
        fail(failure, "error")
        failure["error"] = (
            'AcquisitionError: nvim_exec_lua: [0, "Lua: '
            + "/long-harness-location" * 25
            + ":819: required configured executable unavailable: selene"
            + r"\nstack traceback:\n\t[C]: in function 'assert'\n"
            + "trace-tail-evidence" * 50
            + '"]'
        )
        failure["exception_traceback"] = (
            "Traceback (most recent call last):\nfull-trace-evidence\n"
        )
        data = analyze(records, resamples=2048, block_length=1)
        text = self.render(data, width=48)
        self.assertIn("selene", text)
        self.assertIn("configured executable unavailable", " ".join(text.split()))
        self.assertIn("--details", text)
        self.assertIn("--json", text)
        self.assertNotIn("trace-tail-evidence", text)
        self.assertNotIn("nvim_exec_lua", text)
        self.assertNotIn("AcquisitionError", text)
        self.assertNotIn("long-harness-location", text)
        details = self.render(data, details=True)
        self.assertIn("trace-tail-evidence", details)
        self.assertIn("full-trace-evidence", details)
        self.assertIn("nvim_exec_lua", details)
        self.assertIn("long-harness-location", details)

    def test_failure_group_limit_never_hides_total_count(self) -> None:
        records = journal([MS] * 20, warmups=0)
        for block in range(4):
            failure = measured(records, block=block)
            fail(failure, "error")
            failure["error"] = f"distinct-reason-{block}"
        data = analyze(records, resamples=2048, block_length=1)
        text = self.render(data)
        self.assertIn("3/4", text)
        self.assertRegex(text.lower(), r"4\s+(?:failed|failures|total)")
        self.assertIn("--details", text)
        self.assertNotIn("distinct-reason-3", text)
        details = self.render(data, details=True)
        for block in range(4):
            self.assertIn(f"distinct-reason-{block}", details)

    def test_details_are_an_alternative_with_full_statistics_and_no_host_dump(
        self,
    ) -> None:
        data = report([value * MS for value in range(10, 30)], [10 * MS] * 20)
        data["metadata"]["host"] = {
            "cpu_affinity": [2, 4],
            "secret-host-token": "raw-host-evidence",
        }
        default = self.render(data)
        details = self.render(data, details=True)
        self.assertNotIn("raw-host-evidence", default)
        self.assertNotIn("cpu_affinity", default)
        self.assertNotIn("rng_stream", default)
        for label in ("mean", "median", "mad", "p90", "p95", "lag", "difference"):
            self.assertIn(label, details.lower())
        self.assertNotIn("raw-host-evidence", details)
        self.assertEqual(details.count("editing"), 1)
        self.assertNotIn("MAD", default)

    def test_sensitivity_override_and_missing_plan_remain_prominent(self) -> None:
        data = report([MS] * 20)
        data["analysis_overrides"] = {
            "stored_plan": None,
            "effective_plan": {"confidence": 0.95},
            "overrides": {"confidence": 0.95},
        }
        for details in (False, True):
            text = self.render(data, details=details).lower()
            self.assertIn("sensitivity", text)
            self.assertIn("confidence", text)
            self.assertRegex(text, r"no recorded|not predeclared")

    def test_evidence_controls_and_markup_remain_literal_in_all_modes(self) -> None:
        name = "[red]work[/red]:rocket:\x1b[2J\r\u202eunsafe\u2066"
        records = journal([MS] * 20, names=(name,))
        failure = measured(records)
        fail(failure, "error")
        failure["error"] = "[bold]tool[/bold]\x1b]8;;https://unsafe\x07bad\u202e"
        failure["exception_traceback"] = "[green]trace[/green]\x1b[31m\r\u2069"
        data = analyze(records, resamples=2048, block_length=1)
        data["warnings"].append("[blue]warning[/blue]\x9b2J\u202d")
        for details in (False, True):
            with self.subTest(details=details):
                text = self.render(data, width=120, details=details)
                self.assertIn("[red]work[/red]", text)
                self.assertIn(":rocket:", text)
                self.assertIn("[bold]tool[/bold]", text)
                self.assertIn("[blue]warning[/blue]", text)
                self.assertIn(r"\x1b", text)
                self.assertIn(r"\u202e", text)
                self.assertFalse(
                    any(
                        unicodedata.category(character)
                        in {"Cc", "Cf", "Cs", "Zl", "Zp"}
                        for character in text
                        if character != "\n"
                    )
                )

    def test_narrow_cards_and_wide_tables_keep_full_names_and_uncertainty(self) -> None:
        name = "firstmark " + " ".join(f"segment{i}" for i in range(12)) + " finalmark"
        data = analyze(
            journal([80 * MS] * 20, [100 * MS] * 20, names=(name,)),
            resamples=2048,
            block_length=1,
        )
        for width in (48, 80, 120, 180):
            with self.subTest(width=width):
                text = self.render(data, width=width)
                for part in name.split():
                    self.assertIn(part, text)
                self.assertRegex(text.lower(), r"faster|improvement")
                self.assertIn("-20%", text)
                self.assertIn("[", text)
                self.assertIn("]", text)
                self.assertNotIn("…", text)
                self.assertLessEqual(
                    max(
                        sum(
                            (
                                0
                                if unicodedata.combining(character)
                                else (
                                    2
                                    if unicodedata.east_asian_width(character)
                                    in {"W", "F"}
                                    else 1
                                )
                            )
                            for character in line
                        )
                        for line in text.splitlines()
                    ),
                    min(width, 120),
                )

    def test_report_and_nested_failure_evidence_are_not_mutated(self) -> None:
        records = journal([MS] * 20)
        fail(measured(records), "error")
        measured(records)["last_screen"] = {"grid": [["[red]", "\x1b"]]}
        data = analyze(records, resamples=2048, block_length=1)
        before = deepcopy(data)
        for details in (False, True):
            self.render(data, width=48, details=details)
        self.assertEqual(data, before)

    def test_rendering_does_not_walk_or_copy_rich_evidence(self) -> None:
        class Evidence(dict):
            def __deepcopy__(self, memo: dict) -> object:
                raise AssertionError("rendering copied retained evidence")

            def __repr__(self) -> str:
                raise AssertionError("rendering dumped retained evidence")

            def items(self) -> object:
                raise AssertionError("rendering traversed retained evidence")

        data = report([MS] * 20)
        data["metadata"]["host"] = Evidence(raw="host")
        data["metadata"]["fixture"] = Evidence(raw="fixture")
        for details in (False, True):
            self.render(data, details=details)


class PlainReportTests(ReportCases, unittest.TestCase):
    pass


@unittest.skipUnless(importlib.util.find_spec("rich"), "optional Rich is not installed")
class RichReportTests(ReportCases, unittest.TestCase):
    plain = False


class OutputPolicyTests(unittest.TestCase):
    def test_plain_and_redirected_output_do_not_import_rich(self) -> None:
        original_import = builtins.__import__
        imports = []

        def optional_import(name: str, *args: object, **kwargs: object) -> object:
            if name == "rich" or name.startswith("rich."):
                imports.append(name)
                raise ImportError("Rich deliberately unavailable")
            return original_import(name, *args, **kwargs)

        data = report([MS] * 20)
        for plain, stream in ((True, Terminal()), (False, io.StringIO())):
            with self.subTest(plain=plain), patch(
                "builtins.__import__", side_effect=optional_import
            ):
                print_report(data, plain=plain, file=stream, width=120)
                self.assertIn("editing", stream.getvalue())
        self.assertEqual(imports, [])

    def test_missing_rich_and_limited_terminals_use_concise_ansi_free_fallback(
        self,
    ) -> None:
        original_import = builtins.__import__

        def optional_import(name: str, *args: object, **kwargs: object) -> object:
            if name == "rich" or name.startswith("rich."):
                raise ImportError("Rich deliberately unavailable")
            return original_import(name, *args, **kwargs)

        data = report([MS] * 20)
        for term in ("xterm-256color", "dumb", "unknown"):
            stream = Terminal()
            with self.subTest(term=term), patch.dict(os.environ, {"TERM": term}), patch(
                "builtins.__import__", side_effect=optional_import
            ):
                print_report(data, file=stream, width=120)
            text = stream.getvalue()
            self.assertIn("editing", text)
            self.assertNotIn("\x1b", text)
            self.assertNotIn("rng_stream", text)
            self.assertNotIn("MAD", text)

    def test_stream_default_is_resolved_at_call_time_without_stderr_writes(
        self,
    ) -> None:
        data = report([MS] * 20)
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch("sys.stdout", stdout), patch("sys.stderr", stderr):
            print_report(data, plain=True, width=120)
        self.assertIn("editing", stdout.getvalue())
        self.assertEqual(stderr.getvalue(), "")


if __name__ == "__main__":
    unittest.main()
