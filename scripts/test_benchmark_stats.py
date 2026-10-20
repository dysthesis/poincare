from __future__ import annotations

import json
import math
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

from scripts.benchmark_stats import BenchmarkDataError, analyze, load_records, render

MS = 1_000_000


def journal(
    candidate: list[int],
    baseline: list[int] | None = None,
    *,
    warmups: int = 1,
    names: tuple[str, ...] = ("editing",),
    warmup_latency: int = 999_000 * MS,
) -> list[dict]:
    """An independently specified, balanced experiment with changing round order."""
    targets = ["candidate"] if baseline is None else ["baseline", "candidate"]
    if baseline is not None and len(baseline) != len(candidate):
        raise ValueError("test fixture needs complete pairs")
    schedule = []
    observations = []
    for phase, count in (("warmup", warmups), ("measure", len(candidate))):
        for block in range(count):
            for name in names if block % 2 == 0 else names[::-1]:
                for target in targets if block % 2 == 0 else targets[::-1]:
                    item = {
                        "phase": phase,
                        "block": block,
                        "workload": name,
                        "target": target,
                    }
                    schedule.append(item)
                    values = candidate if target == "candidate" else baseline
                    latency = warmup_latency if phase == "warmup" else values[block]
                    observations.append(
                        {
                            "type": "observation",
                            **item,
                            "status": "ok",
                            "latency_ns": latency,
                            "error": None,
                            "elapsed_ns": latency + 1,
                            "oracle": {"checked": True},
                        }
                    )
    return [
        {
            "type": "manifest",
            "format": "poincare-benchmark/v1",
            "seed": 17,
            "repeat": len(candidate),
            "warmups": warmups,
            "targets": targets,
            "workloads": [{"name": name, "suite": "core"} for name in names],
            "schedule": schedule,
            "metadata": {"state": "warm", "clock": "perf_counter_ns"},
        },
        *observations,
        {"type": "end", "complete": True},
    ]


def measured(records: list[dict], target: str = "candidate", block: int = 0) -> dict:
    return next(
        row
        for row in records[1:-1]
        if row["phase"] == "measure"
        and row["target"] == target
        and row["block"] == block
    )


def fail(row: dict, status: str) -> None:
    row.update(
        status=status,
        latency_ns=None,
        error=f"deliberate {status}",
        stderr="tool evidence",
    )


def result(records: list[dict], **options: object) -> dict:
    return analyze(records, resamples=2048, **options)


class JournalValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.records = journal([10 * MS, 12 * MS, 11 * MS], [9 * MS, 10 * MS, 10 * MS])

    def test_replay_is_json_safe_and_does_not_mutate_evidence(self) -> None:
        original = deepcopy(self.records)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "complete.jsonl"
            path.write_text("".join(json.dumps(row) + "\n" for row in self.records))
            replayed = load_records(path)
        report = result(replayed)
        self.assertTrue(report["valid"])
        self.assertEqual(json.loads(json.dumps(report, allow_nan=False)), report)
        self.assertEqual(self.records, original)
        self.assertEqual(replayed, original)

    def test_decoded_mutable_records_are_validated_when_analyzed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "complete.jsonl"
            path.write_text("".join(json.dumps(row) + "\n" for row in self.records))
            records = load_records(path)
        measured(records)["block"] = 200
        with self.assertRaises(BenchmarkDataError):
            result(records)

    def test_missing_duplicate_or_false_end_markers_are_not_complete_runs(self) -> None:
        variants = [
            self.records[:-1],
            self.records + [{"type": "end", "complete": True}],
            self.records[:-1] + [{"type": "end", "complete": False}],
            self.records[:-1] + [{"type": "end", "complete": "true"}],
            self.records[:-1] + [{"type": "end", "complete": 1}],
            [self.records[0], self.records[-1], *self.records[1:]],
        ]
        for records in variants:
            with self.subTest(records=records), self.assertRaises(BenchmarkDataError):
                result(records)

    def test_missing_duplicate_extra_and_reordered_observations_are_rejected(
        self,
    ) -> None:
        variants = []
        missing = deepcopy(self.records)
        del missing[2]
        variants.append(missing)
        duplicate = deepcopy(self.records)
        duplicate.insert(2, deepcopy(duplicate[1]))
        variants.append(duplicate)
        replaced = deepcopy(self.records)
        replaced[2] = deepcopy(replaced[1])
        variants.append(replaced)
        reordered = deepcopy(self.records)
        reordered[3], reordered[4] = reordered[4], reordered[3]
        variants.append(reordered)
        extra_manifest = deepcopy(self.records)
        extra_manifest[2] = deepcopy(extra_manifest[0])
        variants.append(extra_manifest)
        for records in variants:
            with self.subTest(records=records), self.assertRaises(BenchmarkDataError):
                result(records)

    def test_schedule_requires_both_phases_and_every_target_workload_block(
        self,
    ) -> None:
        for phase in ("warmup", "measure"):
            for target in ("baseline", "candidate"):
                records = journal([MS] * 4, [MS] * 4, names=("editing", "picker"))
                index = next(
                    i
                    for i, item in enumerate(records[0]["schedule"])
                    if item["phase"] == phase
                    and item["target"] == target
                    and item["workload"] == "picker"
                )
                del records[0]["schedule"][index]
                del records[index + 1]
                with self.subTest(phase=phase, target=target), self.assertRaisesRegex(
                    BenchmarkDataError, "incomplete schedule"
                ):
                    result(records)

    def test_duplicate_extra_and_invalid_schedule_identifiers_are_rejected(
        self,
    ) -> None:
        for field, value in (
            ("block", -1),
            ("block", True),
            ("block", 3),
            ("phase", "startup"),
            ("workload", "unselected"),
            ("target", "third"),
        ):
            records = deepcopy(self.records)
            records[0]["schedule"][0][field] = value
            records[1][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(
                BenchmarkDataError
            ):
                result(records)
        records = deepcopy(self.records)
        records[0]["schedule"][1] = deepcopy(records[0]["schedule"][0])
        with self.assertRaisesRegex(BenchmarkDataError, "duplicate schedule"):
            result(records)

    def test_pairs_must_be_adjacent_even_when_schedule_and_observations_agree(
        self,
    ) -> None:
        records = journal([MS] * 4, [MS] * 4, names=("editing", "picker"), warmups=0)
        records[0]["schedule"][1], records[0]["schedule"][2] = (
            records[0]["schedule"][2],
            records[0]["schedule"][1],
        )
        records[2], records[3] = records[3], records[2]
        with self.assertRaisesRegex(BenchmarkDataError, "adjacent"):
            result(records)

    def test_rounds_must_be_chronological_and_target_order_balanced(self) -> None:
        records = journal([MS] * 4, [MS] * 4, warmups=0)
        schedule = records[0]["schedule"]
        schedule[:4] = schedule[2:4] + schedule[:2]
        records[1:5] = records[3:5] + records[1:3]
        with self.assertRaisesRegex(BenchmarkDataError, "chronological"):
            result(records)
        records = journal([MS] * 4, [MS] * 4, warmups=0)
        for index in (2, 6):
            schedule = records[0]["schedule"]
            schedule[index], schedule[index + 1] = schedule[index + 1], schedule[index]
            records[index + 1], records[index + 2] = (
                records[index + 2],
                records[index + 1],
            )
        with self.assertRaisesRegex(BenchmarkDataError, "unbalanced"):
            result(records)

    def test_manifest_types_and_catalog_are_strict(self) -> None:
        for field, value in (
            ("seed", True),
            ("repeat", True),
            ("repeat", 0),
            ("repeat", 3.0),
            ("warmups", -1),
            ("warmups", False),
            ("targets", ["candidate", "baseline"]),
            ("targets", ["candidate", "candidate"]),
            ("targets", []),
            ("workloads", []),
            ("workloads", [{"name": "editing"}, {"name": "editing"}]),
            ("metadata", None),
        ):
            records = deepcopy(self.records)
            records[0][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(
                BenchmarkDataError
            ):
                result(records)

    def test_success_requires_positive_finite_integer_latency_and_null_error(
        self,
    ) -> None:
        for latency in (None, 0, -1, True, 3.5, float("nan"), float("inf"), 10**400):
            records = deepcopy(self.records)
            measured(records)["latency_ns"] = latency
            with self.subTest(latency=latency), self.assertRaises(BenchmarkDataError):
                result(records)
        for field, value in (
            ("status", "skipped"),
            ("error", "not actually successful"),
        ):
            records = deepcopy(self.records)
            measured(records)[field] = value
            with self.subTest(field=field), self.assertRaises(BenchmarkDataError):
                result(records)
        for field in ("status", "latency_ns", "error", "target", "block"):
            records = deepcopy(self.records)
            del measured(records)[field]
            with self.subTest(missing=field), self.assertRaises(BenchmarkDataError):
                result(records)

    def test_timeouts_cannot_use_elapsed_time_as_a_successful_latency(self) -> None:
        for status in ("error", "timeout"):
            records = deepcopy(self.records)
            row = measured(records)
            row.update(status=status, error="deadline", latency_ns=row["elapsed_ns"])
            with self.subTest(status=status), self.assertRaisesRegex(
                BenchmarkDataError, "null latency_ns"
            ):
                result(records)

    def test_nonfinite_or_nonjson_evidence_is_rejected_not_hidden(self) -> None:
        for value in (float("nan"), float("inf"), -float("inf"), (1, 2), {1: "key"}):
            records = deepcopy(self.records)
            records[0]["metadata"]["nested"] = {"evidence": [value]}
            with self.subTest(value=value), self.assertRaises(BenchmarkDataError):
                result(records)
        records = deepcopy(self.records)
        measured(records)["oracle"] = {"duration": float("nan")}
        with self.assertRaises(BenchmarkDataError):
            result(records)

    def test_loader_rejects_invalid_json_duplicates_nonfinite_and_interruption(
        self,
    ) -> None:
        complete = "".join(json.dumps(row) + "\n" for row in self.records)
        variants = [
            complete + '{"type":',
            complete.replace('"seed": 17', '"seed": NaN'),
            complete.replace('"seed": 17', '"seed": 1e999'),
            complete.replace('"seed": 17', '"seed": 17, "seed": 18'),
            complete + "\n",
            "".join(json.dumps(row) + "\n" for row in self.records[:-1]),
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "broken.jsonl"
            for text in variants:
                path.write_text(text)
                with self.subTest(text=text), self.assertRaises(BenchmarkDataError):
                    load_records(path)
            with self.assertRaises(BenchmarkDataError):
                load_records(Path(directory) / "missing.jsonl")


class StatisticalBehaviorTests(unittest.TestCase):
    def test_constant_paired_ratio_survives_large_shared_process_variability(
        self,
    ) -> None:
        baseline = [value * MS for value in (1, 1000, 3, 700, 11, 500)] * 5
        report = result(journal([2 * value for value in baseline], baseline))
        workload = report["workloads"][0]
        comparison = workload["comparison"]
        self.assertEqual(workload["decision"], "regression")
        self.assertEqual(comparison["n_pairs"], 30)
        self.assertAlmostEqual(comparison["candidate_over_baseline"], 2)
        self.assertAlmostEqual(comparison["percent_change"], 100)
        for endpoint in comparison["ratio_ci"]:
            self.assertAlmostEqual(endpoint, 2)
        self.assertAlmostEqual(
            comparison["mean_difference_ns"],
            sum(baseline) / len(baseline),
            delta=0.000001,
        )

    def test_constant_absolute_offset_and_geometric_not_arithmetic_effect(self) -> None:
        baseline = [100 * MS, 200 * MS] * 15
        candidate = [value + 10 * MS for value in baseline]
        comparison = result(journal(candidate, baseline))["workloads"][0]["comparison"]
        self.assertAlmostEqual(
            comparison["candidate_over_baseline"], math.sqrt(1.1 * 1.05)
        )
        self.assertNotAlmostEqual(comparison["candidate_over_baseline"], 160 / 150)
        self.assertEqual(comparison["mean_difference_ns"], 10 * MS)
        self.assertEqual(comparison["difference_ci_ns"], [10 * MS, 10 * MS])

    def test_descriptives_are_per_process_with_unscaled_mad_and_sample_sd(self) -> None:
        target = result(journal([value * MS for value in (1, 2, 3, 4)], warmups=0))[
            "workloads"
        ][0]["targets"]["candidate"]
        summary = target["descriptive"]
        self.assertEqual(summary["n"], 4)
        self.assertEqual(summary["mean_ns"], 2.5 * MS)
        self.assertEqual(summary["median_ns"], 2.5 * MS)
        self.assertAlmostEqual(summary["sd_ns"], math.sqrt(5 / 3) * MS)
        self.assertEqual(summary["mad_ns"], MS)
        self.assertEqual(summary["min_ns"], MS)
        self.assertEqual(summary["max_ns"], 4 * MS)
        self.assertAlmostEqual(summary["p90_ns"], 3.7 * MS)
        self.assertAlmostEqual(summary["p95_ns"], 3.85 * MS)
        self.assertNotIn("p99_ns", summary)
        singleton = result(journal([MS], warmups=0))["workloads"][0]["targets"][
            "candidate"
        ]
        self.assertIsNone(singleton["descriptive"]["sd_ns"])
        self.assertIsNone(singleton["median_ci_ns"])

    def test_warmups_never_enter_means_intervals_or_temporal_diagnostics(self) -> None:
        values = [value * MS for value in range(1, 25)]
        first = result(journal(values, warmups=3, warmup_latency=MS))
        second = result(journal(values, warmups=3, warmup_latency=10**12 * MS))
        self.assertEqual(first, second)
        summary = first["workloads"][0]["targets"]["candidate"]["descriptive"]
        self.assertEqual(summary["n"], 24)
        self.assertEqual(
            first["workloads"][0]["targets"]["candidate"]["measured_blocks"],
            list(range(24)),
        )
        self.assertEqual(summary["mean_ns"], 12.5 * MS)

    def test_outlying_processes_are_not_trimmed_or_replaced(self) -> None:
        values = [MS] * 29 + [1000 * MS]
        summary = result(journal(values))["workloads"][0]["targets"]["candidate"][
            "descriptive"
        ]
        self.assertEqual(summary["n"], 30)
        self.assertEqual(summary["max_ns"], 1000 * MS)
        self.assertEqual(summary["mean_ns"], 1029 * MS / 30)

    def test_failures_in_either_phase_or_target_forbid_survivor_inference(self) -> None:
        for phase in ("warmup", "measure"):
            for target in ("baseline", "candidate"):
                for status in ("error", "timeout"):
                    records = journal([11 * MS] * 24, [10 * MS] * 24)
                    row = next(
                        item
                        for item in records[1:-1]
                        if item["phase"] == phase and item["target"] == target
                    )
                    fail(row, status)
                    report = result(records)
                    workload = report["workloads"][0]
                    with self.subTest(phase=phase, target=target, status=status):
                        self.assertFalse(report["valid"])
                        self.assertFalse(workload["valid"])
                        self.assertEqual(workload["decision"], "invalid")
                        self.assertIsNone(workload["comparison"])
                        self.assertEqual(workload["failures"], [row])
                        self.assertEqual(
                            workload["targets"][target]["counts"][phase][status], 1
                        )
                        for details in workload["targets"].values():
                            self.assertIsNone(details["median_ci_ns"])
                        details = workload["targets"][target]
                        self.assertEqual(
                            details["descriptive"]["n"],
                            23 if phase == "measure" else 24,
                        )
                        self.assertEqual(
                            details["descriptive"]["successful_only"],
                            phase == "measure",
                        )
                        self.assertEqual(details["measured_blocks"], list(range(24)))
                        if phase == "measure":
                            self.assertIsNone(details["diagnostics"])

    def test_all_timeouts_have_no_latency_descriptives_or_comparison(self) -> None:
        records = journal([MS] * 4, warmups=0)
        for row in records[1:-1]:
            fail(row, "timeout")
        report = result(records)
        details = report["workloads"][0]["targets"]["candidate"]
        self.assertFalse(report["valid"])
        self.assertEqual(details["descriptive"]["n"], 0)
        self.assertIsNone(details["descriptive"]["mean_ns"])
        self.assertIsNone(details["median_ci_ns"])
        text = render(report)
        self.assertIn("INVALID", text)
        self.assertIn("timeout=4", text)
        self.assertIn("deliberate timeout", text)
        json.dumps(report, allow_nan=False)

    def test_render_labels_recorded_plan_and_even_equal_sensitivity_overrides(
        self,
    ) -> None:
        report = result(journal([MS] * 20))
        plan = {
            "resamples": 2048,
            "confidence": 0.95,
            "practical": 0.05,
            "seed": 20261020,
            "block_length": None,
        }
        report["analysis_overrides"] = {
            "stored_plan": deepcopy(plan),
            "effective_plan": deepcopy(plan),
            "overrides": {},
        }
        self.assertIn("recorded pre-acquisition plan", render(report))
        self.assertNotIn("SENSITIVITY OVERRIDES", render(report))
        report["analysis_overrides"]["overrides"] = {"confidence": 0.95}
        self.assertIn("SENSITIVITY OVERRIDES (confidence)", render(report))
        report["analysis_overrides"]["stored_plan"] = None
        self.assertIn("no recorded pre-acquisition plan", render(report))

    def test_practical_decisions_and_minimum_complete_pair_gate(self) -> None:
        for ratio, expected in (
            (1.2, "regression"),
            (0.8, "improvement"),
            (1.02, "within practical band"),
        ):
            records = journal([round(100 * MS * ratio)] * 20, [100 * MS] * 20)
            with self.subTest(ratio=ratio):
                self.assertEqual(result(records)["workloads"][0]["decision"], expected)
        few = result(journal([200 * MS] * 19, [100 * MS] * 19, warmups=10))[
            "workloads"
        ][0]
        self.assertEqual(few["comparison"]["n_pairs"], 19)
        self.assertEqual(few["decision"], "exploratory")
        same = result(journal([100 * MS] * 20, [100 * MS] * 20), practical=0)[
            "workloads"
        ][0]
        self.assertEqual(same["decision"], "within practical band")
        varied = journal([50 * MS, 200 * MS] * 15, [100 * MS] * 30)
        uncertain = analyze(varied, block_length=1, resamples=2000)["workloads"][0]
        self.assertEqual(uncertain["decision"], "inconclusive")

    def test_one_resample_cannot_support_practical_labels_despite_complete_pairs(
        self,
    ) -> None:
        baseline = [100 * MS] * 30
        candidates = (
            [value * MS for value in range(115, 145)],
            [value * MS for value in range(55, 85)],
            [99 * MS, 101 * MS] * 15,
        )
        for candidate in candidates:
            with self.subTest(candidate=candidate):
                report = analyze(
                    journal(candidate, baseline), resamples=1, block_length=1
                )
                workload = report["workloads"][0]
                self.assertTrue(report["valid"])
                self.assertTrue(workload["valid"])
                self.assertEqual(workload["decision"], "exploratory")
                self.assertFalse(report["statistics"]["adequate_tail_support"])
                self.assertEqual(workload["comparison"]["n_pairs"], 30)
                interval = workload["comparison"]["ratio_ci"]
                self.assertIsNotNone(interval)
                self.assertEqual(interval[0], interval[1])
                self.assertIsNotNone(workload["targets"]["candidate"]["median_ci_ns"])
                self.assertIn(
                    "Underresolved bootstrap tails", " ".join(workload["warnings"])
                )
                self.assertIn("practical decisions are suppressed", render(report))

    def test_single_target_does_not_invent_a_baseline_comparison(self) -> None:
        report = result(journal([MS] * 30))
        workload = report["workloads"][0]
        self.assertEqual(report["statistics"]["primary_endpoint"], "candidate_median")
        self.assertIn("Primary median interval plan", render(report))
        self.assertTrue(workload["valid"])
        self.assertEqual(workload["decision"], "descriptive")
        self.assertIsNone(workload["comparison"])
        self.assertEqual(workload["targets"]["candidate"]["median_ci_ns"], [MS, MS])

    def test_invalid_workloads_stay_in_the_multiplicity_family(self) -> None:
        records = journal([12 * MS] * 24, [10 * MS] * 24, names=("editing", "picker"))
        fail(next(row for row in records[1:-1] if row["workload"] == "picker"), "error")
        report = result(records)
        settings = report["statistics"]
        self.assertEqual(settings["family_size"], 2)
        self.assertEqual(settings["primary_endpoint"], "paired_ratio")
        self.assertIn("no joint coverage claim", settings["secondary_interval_scope"])
        self.assertIn("Primary ratio interval plan", render(report))
        self.assertIn("Secondary median/absolute-difference", render(report))
        self.assertAlmostEqual(settings["per_workload_alpha"], 0.025)
        self.assertAlmostEqual(settings["interval_confidence"], 0.975)
        self.assertEqual(report["workloads"][0]["decision"], "regression")
        self.assertEqual(report["workloads"][1]["decision"], "invalid")
        self.assertFalse(report["valid"])

    def test_adjusted_tail_support_is_recorded_and_warned(self) -> None:
        records = journal([MS] * 20, names=("editing", "picker", "startup"))
        report = analyze(records, resamples=10)
        settings = report["statistics"]
        self.assertFalse(settings["adequate_tail_support"])
        self.assertAlmostEqual(
            settings["expected_resamples_per_tail"], 10 * 0.05 / 3 / 2
        )
        self.assertTrue(report["warnings"])
        supported = analyze(records, resamples=2400)
        self.assertTrue(supported["statistics"]["adequate_tail_support"])

    def test_failed_selected_endpoint_still_counts_against_tail_decision_support(
        self,
    ) -> None:
        baseline = [100 * MS] * 24
        candidate = [120 * MS] * 24
        single = analyze(journal(candidate, baseline), resamples=1000)
        self.assertTrue(single["statistics"]["adequate_tail_support"])
        self.assertEqual(single["workloads"][0]["decision"], "regression")
        records = journal(candidate, baseline, names=("editing", "picker"))
        fail(next(row for row in records[1:-1] if row["workload"] == "picker"), "error")
        family = analyze(records, resamples=1000)
        self.assertEqual(family["statistics"]["family_size"], 2)
        self.assertFalse(family["statistics"]["adequate_tail_support"])
        self.assertTrue(family["workloads"][0]["valid"])
        self.assertEqual(family["workloads"][0]["decision"], "exploratory")
        self.assertEqual(family["workloads"][1]["decision"], "invalid")
        self.assertIsNotNone(family["workloads"][0]["comparison"]["ratio_ci"])

    def test_seed_reproduces_resampling_and_not_only_point_estimates(self) -> None:
        baseline = [(value + 20) * MS for value in range(41)]
        candidate = [
            value + (index % 9 - 4) * MS for index, value in enumerate(baseline)
        ]
        records = journal(candidate, baseline)
        first = result(records, seed=71, block_length=1)
        self.assertEqual(first, result(records, seed=71, block_length=1))
        second = result(records, seed=72, block_length=1)
        self.assertEqual(
            first["workloads"][0]["comparison"]["candidate_over_baseline"],
            second["workloads"][0]["comparison"]["candidate_over_baseline"],
        )
        self.assertNotEqual(
            first["workloads"][0]["comparison"]["ratio_ci"],
            second["workloads"][0]["comparison"]["ratio_ci"],
        )

    def test_full_length_blocks_suppress_intervals_and_practical_decisions(
        self,
    ) -> None:
        baseline = [100 * MS] * 24
        candidate = [value * MS for value in range(80, 104)]
        records = journal(candidate, baseline)
        circular_report = result(records, block_length=24)
        circular = circular_report["workloads"][0]
        independent = result(records, block_length=1)["workloads"][0]
        self.assertTrue(circular_report["valid"])
        self.assertFalse(circular_report["statistics"]["intervals_available"])
        self.assertEqual(
            circular_report["statistics"]["resamples_per_valid_workload"], 0
        )
        self.assertEqual(
            circular_report["statistics"]["expected_resamples_per_tail"], 0
        )
        self.assertIn("suppressed", " ".join(circular_report["warnings"]))
        self.assertEqual(circular["decision"], "exploratory")
        self.assertEqual(
            circular["targets"]["candidate"]["descriptive"]["median_ns"], 91.5 * MS
        )
        self.assertIsNone(circular["targets"]["candidate"]["median_ci_ns"])
        self.assertIsNone(circular["comparison"]["ratio_ci"])
        self.assertIsNone(circular["comparison"]["difference_ci_ns"])
        self.assertEqual(circular["comparison"]["mean_difference_ns"], -8.5 * MS)
        self.assertEqual(
            circular["comparison"]["candidate_over_baseline"],
            independent["comparison"]["candidate_over_baseline"],
        )
        self.assertLess(*independent["targets"]["candidate"]["median_ci_ns"])
        self.assertLess(*independent["comparison"]["ratio_ci"])
        self.assertLess(*independent["comparison"]["difference_ci_ns"])

    def test_two_process_default_keeps_heuristic_but_has_no_degenerate_intervals(
        self,
    ) -> None:
        report = result(journal([120 * MS, 240 * MS], [100 * MS, 200 * MS]))
        workload = report["workloads"][0]
        self.assertEqual(report["statistics"]["block_length"], 2)
        self.assertEqual(workload["decision"], "exploratory")
        self.assertAlmostEqual(workload["comparison"]["candidate_over_baseline"], 1.2)
        self.assertIsNone(workload["comparison"]["ratio_ci"])
        self.assertIsNone(workload["targets"]["candidate"]["median_ci_ns"])

    def test_block_intervals_reflect_clustered_temporal_noise(self) -> None:
        # A persistent fast/slow host regime, not sixty independent key events.
        records = journal([80 * MS] * 30 + [120 * MS] * 30, [100 * MS] * 60)
        independent = analyze(records, block_length=1, resamples=1200, seed=41)[
            "workloads"
        ][0]
        blocked = analyze(records, block_length=6, resamples=1200, seed=41)[
            "workloads"
        ][0]
        self.assertGreater(
            blocked["targets"]["candidate"]["diagnostics"]["lag1_correlation"], 0.9
        )
        self.assertEqual(
            independent["comparison"]["candidate_over_baseline"],
            blocked["comparison"]["candidate_over_baseline"],
        )
        iid_interval = independent["comparison"]["difference_ci_ns"]
        block_interval = blocked["comparison"]["difference_ci_ns"]
        self.assertGreater(
            block_interval[1] - block_interval[0], iid_interval[1] - iid_interval[0]
        )

    def test_descriptive_serial_and_half_drift_diagnostics_keep_chronology(
        self,
    ) -> None:
        values = [value * MS for value in range(1, 32)]
        report = result(journal(values, warmups=3))
        diagnostic = report["workloads"][0]["targets"]["candidate"]["diagnostics"]
        self.assertAlmostEqual(diagnostic["lag1_correlation"], 1)
        self.assertEqual(diagnostic["first_half_n"], 15)
        self.assertEqual(diagnostic["last_half_n"], 15)
        self.assertEqual(diagnostic["middle_omitted"], 1)
        self.assertEqual(diagnostic["last_minus_first_half"], 16 * MS)
        constant = result(journal([MS] * 24))["workloads"][0]["targets"]["candidate"][
            "diagnostics"
        ]
        self.assertIsNone(constant["lag1_correlation"])
        self.assertEqual(constant["last_minus_first_half"], 0)

    def test_tail_support_labels_and_p99_publication_threshold(self) -> None:
        for count in (99, 100, 999, 1000):
            report = analyze(journal([MS] * count, warmups=0), resamples=2)
            summary = report["workloads"][0]["targets"]["candidate"]["descriptive"]
            with self.subTest(count=count):
                self.assertEqual(summary["p95_low_support"], count < 100)
                self.assertEqual("p99_ns" in summary, count >= 1000)

    def test_unrepresentable_computed_effect_is_an_error_not_infinite_json(
        self,
    ) -> None:
        with self.assertRaises(BenchmarkDataError):
            analyze(journal([10**307] * 20, [1] * 20), resamples=2)

    def test_pure_api_explicit_settings_do_not_inherit_an_incidental_metadata_plan(
        self,
    ) -> None:
        records = journal([120 * MS] * 24, [100 * MS] * 24)
        stored = {
            "resamples": 32,
            "confidence": 0.90,
            "practical": 0.50,
            "seed": 8,
            "block_length": 24,
        }
        records[0]["metadata"]["analysis_plan"] = deepcopy(stored)
        report = analyze(
            records, resamples=2048, practical=0.05, seed=73, block_length=1
        )
        self.assertEqual(report["metadata"]["analysis_plan"], stored)
        self.assertEqual(report["statistics"]["resamples"], 2048)
        self.assertEqual(report["statistics"]["practical"], 0.05)
        self.assertEqual(report["statistics"]["seed"], 73)
        self.assertEqual(report["statistics"]["block_length"], 1)
        self.assertEqual(report["workloads"][0]["decision"], "regression")

    def test_block_policy_and_analysis_options_are_explicit_and_strict(self) -> None:
        records = journal([MS] * 30)
        self.assertEqual(result(records)["statistics"]["block_length"], 4)
        for options in (
            {"resamples": 0},
            {"resamples": True},
            {"resamples": 10**400},
            {"confidence": 1},
            {"confidence": 0},
            {"confidence": float("nan")},
            {"confidence": True},
            {"practical": -0.1},
            {"practical": 1},
            {"practical": float("inf")},
            {"seed": True},
            {"seed": 10**400},
            {"block_length": 0},
            {"block_length": 31},
            {"block_length": 2.5},
            {"block_length": True},
        ):
            with self.subTest(options=options), self.assertRaises(BenchmarkDataError):
                analyze(records, **options)


if __name__ == "__main__":
    unittest.main()
