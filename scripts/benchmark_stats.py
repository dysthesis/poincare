"""Validate and analyze complete workload benchmark journals using only the stdlib.

The process is the sample, the scheduled block is the pairing unit, and failures
invalidate an entire workload rather than creating a survivor-only comparison.
"""

from __future__ import annotations

import json
import math
import random
import statistics
from collections import Counter
from pathlib import Path
from typing import Any

JOURNAL_FORMAT = "poincare-benchmark/v1"
REPORT_FORMAT = "poincare-benchmark-analysis/v1"
MINIMUM_PAIRS = 20
RECOMMENDED_TAIL_RESAMPLES = 20
_IDENTIFIERS = ("phase", "block", "workload", "target")


class BenchmarkDataError(ValueError):
    """The journal or requested analysis cannot support an honest report."""


def _integer(value: Any, label: str, minimum: int | None = None) -> int:
    if type(value) is not int or (minimum is not None and value < minimum):
        bound = f" >= {minimum}" if minimum is not None else ""
        raise BenchmarkDataError(f"{label} must be an integer{bound} (not a boolean)")
    _finite(value, label)
    return value


def _finite(value: Any, label: str) -> float:
    if type(value) not in (int, float):
        raise BenchmarkDataError(f"{label} must be a finite number (not a boolean)")
    try:
        number = float(value)
    except (OverflowError, ValueError) as error:
        raise BenchmarkDataError(f"{label} is outside finite numeric range") from error
    if not math.isfinite(number):
        raise BenchmarkDataError(f"{label} must be finite")
    return number


def _json_value(value: Any, label: str) -> None:
    if value is None or type(value) in (str, bool):
        return
    if type(value) in (int, float):
        _finite(value, label)
        return
    if type(value) is list:
        for index, item in enumerate(value):
            _json_value(item, f"{label}[{index}]")
        return
    if type(value) is dict:
        for key, item in value.items():
            if type(key) is not str:
                raise BenchmarkDataError(f"{label} has a non-string object key")
            _json_value(item, f"{label}.{key}")
        return
    raise BenchmarkDataError(f"{label} is not a JSON value")


def _object(pairs: list[tuple[str, Any]]) -> dict:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise BenchmarkDataError(f"duplicate JSON object key {key!r}")
        result[key] = value
    return result


def _constant(token: str) -> Any:
    raise BenchmarkDataError(f"nonfinite JSON number {token}")


def _parse_integer(token: str) -> int:
    value = int(token)
    _finite(value, "JSON integer")
    return value


def _parse_float(token: str) -> float:
    return _finite(float(token), "JSON number")


def _validate_envelope(records: list[dict]) -> dict:
    if type(records) is not list or not records:
        raise BenchmarkDataError("journal must be a nonempty list of records")
    for index, record in enumerate(records):
        if type(record) is not dict:
            raise BenchmarkDataError(f"record {index + 1} must be an object")
    manifest = records[0]
    if manifest.get("type") != "manifest" or manifest.get("format") != JOURNAL_FORMAT:
        raise BenchmarkDataError(f"first record must be a {JOURNAL_FORMAT} manifest")
    ends = [
        index for index, record in enumerate(records) if record.get("type") == "end"
    ]
    if ends != [len(records) - 1] or records[-1].get("complete") is not True:
        raise BenchmarkDataError(
            "interrupted or malformed journal: require exactly one terminal end marker with complete:true"
        )
    return manifest


def load_records(path: Path) -> list[dict]:
    """Decode finite JSON records with a complete envelope; analyze validates schema."""
    records = []
    line_number = 0
    try:
        with Path(path).open(encoding="utf-8") as stream:
            for line_number, line in enumerate(stream, 1):
                try:
                    record = json.loads(
                        line,
                        object_pairs_hook=_object,
                        parse_constant=_constant,
                        parse_int=_parse_integer,
                        parse_float=_parse_float,
                    )
                except (ValueError, RecursionError) as error:
                    raise BenchmarkDataError(
                        f"{path}: line {line_number}: invalid JSON: {error}"
                    ) from error
                records.append(record)
    except (OSError, UnicodeError) as error:
        raise BenchmarkDataError(
            f"{path}: cannot read journal near line {line_number + 1}: {error}"
        ) from error
    _validate_envelope(records)
    return records


def _key(item: dict, label: str) -> tuple[str, int, str, str]:
    for field in _IDENTIFIERS:
        if field not in item:
            raise BenchmarkDataError(f"{label} is missing {field}")
    if item["phase"] not in ("warmup", "measure"):
        raise BenchmarkDataError(f"{label}.phase must be warmup or measure")
    _integer(item["block"], f"{label}.block", 0)
    for field in ("workload", "target"):
        if type(item[field]) is not str or not item[field]:
            raise BenchmarkDataError(f"{label}.{field} must be a nonempty string")
    return tuple(item[field] for field in _IDENTIFIERS)  # type: ignore[return-value]


def _validate_records(records: list[dict]) -> dict:
    manifest = _validate_envelope(records)
    try:
        _json_value(records, "journal")
    except RecursionError as error:
        raise BenchmarkDataError("journal is too deeply nested or cyclic") from error
    _integer(manifest.get("seed"), "manifest.seed")
    repeat = _integer(manifest.get("repeat"), "manifest.repeat", 1)
    warmups = _integer(manifest.get("warmups"), "manifest.warmups", 0)
    targets = manifest.get("targets")
    if targets not in (["candidate"], ["baseline", "candidate"]):
        raise BenchmarkDataError(
            "manifest.targets must be ['candidate'] or ['baseline', 'candidate']"
        )
    workloads = manifest.get("workloads")
    if type(workloads) is not list or not workloads:
        raise BenchmarkDataError("manifest.workloads must be a nonempty list")
    names = []
    for index, workload in enumerate(workloads):
        if (
            type(workload) is not dict
            or type(workload.get("name")) is not str
            or not workload["name"]
        ):
            raise BenchmarkDataError(
                f"manifest.workloads[{index}] needs a nonempty name"
            )
        names.append(workload["name"])
    if len(set(names)) != len(names):
        raise BenchmarkDataError("manifest has duplicate workload names")
    if type(manifest.get("metadata")) is not dict:
        raise BenchmarkDataError("manifest.metadata must be an object")
    schedule = manifest.get("schedule")
    if type(schedule) is not list:
        raise BenchmarkDataError("manifest.schedule must be a list")
    expected = {
        (phase, block, name, target)
        for phase, count in (("warmup", warmups), ("measure", repeat))
        for block in range(count)
        for name in names
        for target in targets
    }
    seen = set()
    keys = []
    for index, item in enumerate(schedule):
        label = f"schedule item {index + 1}"
        if type(item) is not dict:
            raise BenchmarkDataError(f"{label} must be an object")
        key = _key(item, label)
        if key in seen:
            raise BenchmarkDataError(f"duplicate schedule item: {key}")
        if key not in expected:
            raise BenchmarkDataError(f"extra or out-of-range schedule item: {key}")
        seen.add(key)
        keys.append(key)
    if seen != expected:
        missing = sorted(expected - seen)
        raise BenchmarkDataError(
            f"incomplete schedule: missing {len(missing)} item(s), first {missing[0]}"
        )

    # Chronological rounds and adjacent pairs are part of the experiment, not
    # merely enough identifiers to join otherwise unrelated observations.
    position = 0
    for phase, count in (("warmup", warmups), ("measure", repeat)):
        first_targets: dict[str, Counter] = {name: Counter() for name in names}
        for block in range(count):
            block_names = set()
            for _ in names:
                pair = keys[position : position + len(targets)]
                position += len(targets)
                if any(key[:2] != (phase, block) for key in pair):
                    raise BenchmarkDataError(
                        "schedule must contain chronological phase/block rounds"
                    )
                name = pair[0][2]
                if any(key[2] != name for key in pair) or name in block_names:
                    raise BenchmarkDataError(
                        "schedule must keep each workload's target pair adjacent"
                    )
                if {key[3] for key in pair} != set(targets):
                    raise BenchmarkDataError("schedule target pair is incomplete")
                block_names.add(name)
                first_targets[name][pair[0][3]] += 1
        if len(targets) == 2:
            for name, orders in first_targets.items():
                if abs(orders["baseline"] - orders["candidate"]) > 1:
                    raise BenchmarkDataError(
                        f"unbalanced target order for {phase} workload {name!r}"
                    )

    observations = records[1:-1]
    if len(observations) != len(keys):
        raise BenchmarkDataError(
            f"incomplete or extra observations: expected {len(keys)}, found {len(observations)}"
        )
    for index, (observation, scheduled) in enumerate(zip(observations, keys)):
        label = f"observation {index + 1}"
        if observation.get("type") != "observation":
            raise BenchmarkDataError(f"{label} must have type observation")
        if _key(observation, label) != scheduled:
            raise BenchmarkDataError(
                f"{label} does not match its ordered schedule item"
            )
        status = observation.get("status")
        if status not in ("ok", "error", "timeout"):
            raise BenchmarkDataError(f"{label}.status must be ok, error, or timeout")
        if "error" not in observation or (
            observation["error"] is not None and type(observation["error"]) is not str
        ):
            raise BenchmarkDataError(f"{label}.error must be a string or null")
        if "latency_ns" not in observation:
            raise BenchmarkDataError(f"{label} is missing latency_ns")
        if status == "ok":
            _integer(observation["latency_ns"], f"{label}.latency_ns", 1)
            if observation["error"] is not None:
                raise BenchmarkDataError(
                    f"{label}: an ok observation cannot contain an error"
                )
        elif observation["latency_ns"] is not None:
            raise BenchmarkDataError(
                f"{label}: a failed/timeout observation must have null latency_ns; retain elapsed_ns separately"
            )
    return manifest


def _mean(values: list[float]) -> float:
    try:
        return statistics.fmean(values)
    except OverflowError:
        scale = max(abs(value) for value in values)
        return scale * statistics.fmean(value / scale for value in values)


def _percentile(ordered: list[float], probability: float) -> float:
    position = (len(ordered) - 1) * probability
    lower = math.floor(position)
    upper = math.ceil(position)
    fraction = position - lower
    if fraction == 0:
        return ordered[lower]
    if ordered[lower] < 0 < ordered[upper]:
        return ordered[lower] * (1 - fraction) + ordered[upper] * fraction
    return ordered[lower] + (ordered[upper] - ordered[lower]) * fraction


def _interval(values: list[float], tail: float) -> list[float]:
    ordered = sorted(values)
    return [_percentile(ordered, tail), _percentile(ordered, 1 - tail)]


def _descriptive(values: list[float], expected: int) -> dict:
    count = len(values)
    result: dict[str, Any] = {
        "n": count,
        "expected_n": expected,
        "successful_only": count != expected,
        "mean_ns": None,
        "median_ns": None,
        "sd_ns": None,
        "mad_ns": None,
        "min_ns": None,
        "max_ns": None,
        "p90_ns": None,
        "p95_ns": None,
        "p90_low_support": count < 50,
        "p95_low_support": count < 100,
    }
    if not values:
        return result
    ordered = sorted(values)
    median = _percentile(ordered, 0.5)
    scale = max(values)
    result.update(
        mean_ns=_mean(values),
        median_ns=median,
        sd_ns=(
            scale * statistics.stdev(value / scale for value in values)
            if count > 1
            else None
        ),
        mad_ns=_percentile(sorted(abs(value - median) for value in values), 0.5),
        min_ns=ordered[0],
        max_ns=ordered[-1],
        p90_ns=_percentile(ordered, 0.9),
        p95_ns=_percentile(ordered, 0.95),
    )
    if count >= 1000:
        result["p99_ns"] = _percentile(ordered, 0.99)
    return result


def _lag1(values: list[float]) -> float | None:
    if len(values) < 3:
        return None
    scale = max(abs(value) for value in values)
    if not scale:
        return None
    left = [value / scale for value in values[:-1]]
    right = [value / scale for value in values[1:]]
    left_mean, right_mean = _mean(left), _mean(right)
    left = [value - left_mean for value in left]
    right = [value - right_mean for value in right]
    denominator = math.sqrt(math.fsum(value * value for value in left)) * math.sqrt(
        math.fsum(value * value for value in right)
    )
    if denominator == 0:
        return None
    correlation = math.fsum(a * b for a, b in zip(left, right)) / denominator
    return max(-1.0, min(1.0, correlation))


def _diagnostics(values: list[float], units: str) -> dict:
    half = len(values) // 2
    first = _mean(values[:half]) if half else None
    last = _mean(values[-half:]) if half else None
    return {
        "units": units,
        "lag1_correlation": _lag1(values),
        "first_half_n": half,
        "last_half_n": half,
        "middle_omitted": len(values) % 2,
        "first_half_mean": first,
        "last_half_mean": last,
        "last_minus_first_half": last - first if half else None,
    }


def _indices(rng: random.Random, count: int, length: int) -> list[int]:
    indices = []
    while len(indices) < count:
        start = rng.randrange(count)
        indices.extend(
            (start + offset) % count
            for offset in range(min(length, count - len(indices)))
        )
    return indices


def _bootstrap(
    series: dict[str, list[float]],
    *,
    resamples: int,
    length: int,
    tail: float,
    seed: int,
    name: str,
) -> tuple[dict[str, list[float] | None], dict | None]:
    count = len(next(iter(series.values())))
    rng = random.Random(f"{JOURNAL_FORMAT}:{seed}:{name}")
    medians: dict[str, list[float]] = {target: [] for target in series}
    paired = "baseline" in series
    logs = (
        [
            math.log(c) - math.log(b)
            for b, c in zip(series["baseline"], series["candidate"])
        ]
        if paired
        else []
    )
    differences = (
        [c - b for b, c in zip(series["baseline"], series["candidate"])]
        if paired
        else []
    )
    log_means = []
    difference_means = []
    # Whole-series circular blocks only rotate the data; they cannot estimate
    # sampling uncertainty, even when the observed values vary.
    for _ in range(resamples if length < count else 0):
        indices = _indices(rng, count, length)
        for target, values in series.items():
            medians[target].append(
                _percentile(sorted(values[index] for index in indices), 0.5)
            )
        if paired:
            # The exact same circular blocks feed both paired estimands.
            log_means.append(_mean([logs[index] for index in indices]))
            difference_means.append(_mean([differences[index] for index in indices]))
    intervals = {
        target: _interval(values, tail) if values else None
        for target, values in medians.items()
    }
    if not paired:
        return intervals, None
    ratio = math.exp(_mean(logs))
    comparison = {
        "n_pairs": count,
        "candidate_over_baseline": ratio,
        "relative_change": ratio - 1,
        "percent_change": (ratio - 1) * 100,
        "ratio_ci": (
            [math.exp(value) for value in _interval(log_means, tail)]
            if log_means
            else None
        ),
        "mean_difference_ns": _mean(differences),
        "difference_ci_ns": (
            _interval(difference_means, tail) if difference_means else None
        ),
        "diagnostics": {
            "log_ratio": _diagnostics(logs, "log(candidate/baseline)"),
            "difference": _diagnostics(differences, "ns"),
        },
    }
    return intervals, comparison


def analyze(
    records: list[dict],
    *,
    resamples: int = 20000,
    confidence: float = 0.95,
    practical: float = 0.05,
    seed: int = 20261020,
    block_length: int | None = None,
) -> dict:
    """Analyze a complete fixed schedule; do not retry, trim, or pair survivors.

    All selected workloads, including invalid ones, remain in the Bonferroni
    family. Each workload gets a deterministic independent RNG stream by name.
    """
    manifest = _validate_records(records)
    _integer(resamples, "resamples", 1)
    _integer(seed, "seed")
    confidence = _finite(confidence, "confidence")
    practical = _finite(practical, "practical")
    if not 0 < confidence < 1:
        raise BenchmarkDataError("confidence must lie strictly between 0 and 1")
    if not 0 <= practical < 1:
        raise BenchmarkDataError("practical must lie in [0, 1)")
    count = manifest["repeat"]
    length = math.ceil(count ** (1 / 3)) if block_length is None else block_length
    _integer(length, "block_length", 1)
    if length > count:
        raise BenchmarkDataError(
            "block_length cannot exceed the measured process count"
        )
    family_size = len(manifest["workloads"])
    alpha = (1 - confidence) / family_size
    tail = alpha / 2
    effective_resamples = resamples if length < count else 0
    tail_support = effective_resamples * tail
    adequate = tail_support >= RECOMMENDED_TAIL_RESAMPLES
    warnings = []
    if not adequate and effective_resamples:
        warnings.append(
            f"Inadequate adjusted-tail bootstrap support: {tail_support:.3g} expected resamples "
            f"per tail; practical decisions require at least {RECOMMENDED_TAIL_RESAMPLES}. Increase --resamples "
            "before interpreting interval endpoints."
        )
    if length == count:
        warnings.append(
            "Block length equals n: circular resamples only rotate the observed series. "
            "Inferential intervals and practical decisions are suppressed; increasing "
            "resamples cannot restore sampling variation."
        )
    report: dict[str, Any] = {
        "format": REPORT_FORMAT,
        "valid": True,
        "targets": list(manifest["targets"]),
        "repeat": count,
        "warmups": manifest["warmups"],
        "acquisition_seed": manifest["seed"],
        "metadata": manifest["metadata"],
        "statistics": {
            "method": "circular moving-block percentile bootstrap",
            "resamples": resamples,
            "resamples_per_valid_workload": effective_resamples,
            "intervals_available": length < count,
            "seed": seed,
            "rng_stream": f"random.Random('{JOURNAL_FORMAT}:<seed>:<workload>')",
            "block_length": length,
            "block_length_policy": (
                "ceil(n^(1/3)) heuristic" if block_length is None else "explicit"
            ),
            "confidence": confidence,
            "primary_endpoint": (
                "paired_ratio"
                if "baseline" in manifest["targets"]
                else "candidate_median"
            ),
            "secondary_interval_scope": "same per-workload level; no joint coverage claim over all statistics",
            "family_size": family_size,
            "per_workload_alpha": alpha,
            "interval_confidence": 1 - alpha,
            "tail_probability": tail,
            "expected_resamples_per_tail": tail_support,
            "recommended_resamples_per_tail": RECOMMENDED_TAIL_RESAMPLES,
            "adequate_tail_support": adequate,
            "practical": practical,
            "minimum_pairs": MINIMUM_PAIRS,
        },
        "workloads": [],
        "warnings": warnings,
    }
    _json_value(report["statistics"], "statistics")
    # Transpose validated rich records once. Bootstrap kernels never inspect
    # metadata, screens, status strings, or observation dictionaries.
    columns = {
        item["name"]: {
            target: {
                "blocks": [],
                "latency_ns": [],
                "counts": {
                    phase: {"total": 0, "ok": 0, "error": 0, "timeout": 0}
                    for phase in ("warmup", "measure")
                },
            }
            for target in manifest["targets"]
        }
        for item in manifest["workloads"]
    }
    failures_by_workload: dict[str, list[dict]] = {
        item["name"]: [] for item in manifest["workloads"]
    }
    for observation in records[1:-1]:
        name, target = observation["workload"], observation["target"]
        phase, status = observation["phase"], observation["status"]
        column = columns[name][target]
        column["counts"][phase]["total"] += 1
        column["counts"][phase][status] += 1
        if phase == "measure":
            column["blocks"].append(observation["block"])
            column["latency_ns"].append(
                float(observation["latency_ns"]) if status == "ok" else None
            )
        if status != "ok":
            failures_by_workload[name].append(observation)
    try:
        for catalog in manifest["workloads"]:
            name = catalog["name"]
            failures = failures_by_workload[name]
            valid = not failures
            report["valid"] = report["valid"] and valid
            workload: dict[str, Any] = {
                "name": name,
                "catalog": catalog,
                "valid": valid,
                "decision": "invalid" if not valid else "descriptive",
                "targets": {},
                "comparison": None,
                "failures": failures,
                "warnings": [],
            }
            series = {}
            for target in manifest["targets"]:
                column = columns[name][target]
                counts = column["counts"]
                values = column["latency_ns"]
                if counts["measure"]["ok"] != count:
                    values = [value for value in values if value is not None]
                series[target] = values
                workload["targets"][target] = {
                    "counts": counts,
                    "measured_blocks": column["blocks"],
                    "descriptive": _descriptive(values, count),
                    "median_ci_ns": None,
                    # Removing a failure also removes its time gap: do not report
                    # survivor adjacency as the experiment's serial diagnostic.
                    "diagnostics": (
                        _diagnostics(values, "ns") if len(values) == count else None
                    ),
                }
            if not valid:
                workload["warnings"].append(
                    "Errors/timeouts in either phase invalidate this entire workload. "
                    "Successful-only summaries are descriptive, not survivor inference; "
                    "no median intervals or paired comparison are available."
                )
            else:
                medians, comparison = _bootstrap(
                    series,
                    resamples=resamples,
                    length=length,
                    tail=tail,
                    seed=seed,
                    name=name,
                )
                for target in series:
                    workload["targets"][target]["median_ci_ns"] = medians[target]
                if not adequate and length < count:
                    workload["warnings"].append(
                        f"Underresolved bootstrap tails ({tail_support:.3g} expected draws "
                        f"per adjusted tail; require at least {RECOMMENDED_TAIL_RESAMPLES}): "
                        "retained intervals are exploratory and practical decisions are suppressed."
                    )
                workload["comparison"] = comparison
                if comparison is not None:
                    if comparison["ratio_ci"] is None:
                        workload["decision"] = "exploratory"
                        workload["warnings"].append(
                            "Full-length circular blocks provide no uncertainty estimate; "
                            "paired point effects are descriptive only, regardless of sample count."
                        )
                    elif count < MINIMUM_PAIRS:
                        workload["decision"] = "exploratory"
                        workload["warnings"].append(
                            f"Only {count} measured pairs; decisions require at least {MINIMUM_PAIRS}."
                        )
                    elif not adequate:
                        workload["decision"] = "exploratory"
                    else:
                        lower, upper = comparison["ratio_ci"]
                        if lower > 1 + practical:
                            workload["decision"] = "regression"
                        elif upper < 1 - practical:
                            workload["decision"] = "improvement"
                        elif lower >= 1 - practical and upper <= 1 + practical:
                            workload["decision"] = "within practical band"
                        else:
                            workload["decision"] = "inconclusive"
                elif count < MINIMUM_PAIRS:
                    workload["warnings"].append(
                        "Small-sample median intervals are exploratory."
                    )
            if count < 100:
                workload["warnings"].append(
                    "p95 is low-support below 100 measured processes; p99 is omitted below 1000."
                )
            _json_value(workload["targets"], f"report.{name}.targets")
            _json_value(workload["comparison"], f"report.{name}.comparison")
            report["workloads"].append(workload)
    except (OverflowError, ArithmeticError) as error:
        raise BenchmarkDataError(
            "statistical result exceeds finite numeric range"
        ) from error
    return report


def _ms(value: float | None) -> str:
    return "n/a" if value is None else f"{value / 1_000_000:.6g} ms"


def _ci(values: list[float] | None, *, milliseconds: bool = False) -> str:
    if values is None:
        return "unavailable"
    formatter = _ms if milliseconds else lambda value: f"{value:.6g}"
    return f"[{formatter(values[0])}, {formatter(values[1])}]"


def render(report: dict) -> str:
    """Render the analysis without importing Neovim, msgpack, Rich, or Nix."""
    settings = report["statistics"]
    primary = "ratio" if "baseline" in report["targets"] else "median"
    lines = [
        "Workload-first Neovim benchmark (remote-UI flush latency)",
        f"Acquisition: {'VALID' if report['valid'] else 'INVALID'}; "
        f"{report['repeat']} measured processes and {report['warmups']} warmups per target/workload",
        f"Bootstrap: {settings['method']}; B={settings['resamples']} requested, "
        f"{settings['resamples_per_valid_workload']} applied per valid workload; "
        f"L={settings['block_length']} ({settings['block_length_policy']}), seed={settings['seed']}",
        f"Primary {primary} interval plan: {100 * settings['confidence']:.4g}% nominal family target, "
        f"{100 * settings['interval_confidence']:.6g}% per workload; "
        f"Bonferroni family={settings['family_size']} (invalid workloads included)",
        f"Adjusted-tail support: {settings['expected_resamples_per_tail']:.4g} "
        f"resamples/tail; practical ratio band "
        f"[{1 - settings['practical']:.6g}, {1 + settings['practical']:.6g}]",
        "Intervals are approximate and conditional on this host, fixture, state, and short-range dependence model.",
    ]
    if "baseline" in report["targets"]:
        lines.append(
            "Secondary median/absolute-difference intervals share the adjusted level; "
            "joint family-wise coverage across every displayed statistic is not claimed."
        )
    provenance = report.get("analysis_overrides")
    if provenance is not None:
        if provenance["stored_plan"] is None:
            lines.append(
                "Analysis provenance: no recorded pre-acquisition plan; replay settings are not predeclared."
            )
        if provenance["overrides"]:
            names = ", ".join(sorted(provenance["overrides"]))
            lines.append(
                f"Analysis provenance: SENSITIVITY OVERRIDES ({names}); "
                "effective settings are shown above, plan provenance retained in JSON."
            )
        elif provenance["stored_plan"] is not None:
            lines.append(
                "Analysis provenance: recorded pre-acquisition plan (no replay overrides)."
            )
    lines.extend(f"WARNING: {warning}" for warning in report["warnings"])
    for workload in report["workloads"]:
        lines.extend(["", f"{workload['name']}: {workload['decision'].upper()}"])
        for target, details in workload["targets"].items():
            summary = details["descriptive"]
            counts = details["counts"]
            measured = counts["measure"]
            warmup = counts["warmup"]
            lines.append(
                f"  {target}: measured ok={measured['ok']}/{measured['total']} "
                f"error={measured['error']} timeout={measured['timeout']}; "
                f"warmup ok={warmup['ok']}/{warmup['total']} "
                f"error={warmup['error']} timeout={warmup['timeout']}"
            )
            if summary["successful_only"]:
                lines.append(
                    "    SUCCESSFUL-ONLY DESCRIPTIVES; failures have no scored latency"
                )
            lines.append(
                f"    mean {_ms(summary['mean_ns'])}; median {_ms(summary['median_ns'])} "
                f"CI {_ci(details['median_ci_ns'], milliseconds=True)}; "
                f"sample SD {_ms(summary['sd_ns'])}; MAD {_ms(summary['mad_ns'])}"
            )
            lines.append(
                f"    range {_ci([summary['min_ns'], summary['max_ns']], milliseconds=True) if summary['n'] else 'n/a'}; "
                f"p90 {_ms(summary['p90_ns'])}{' (low support)' if summary['p90_low_support'] else ''}; "
                f"p95 {_ms(summary['p95_ns'])}{' (low support)' if summary['p95_low_support'] else ''}"
                + (f"; p99 {_ms(summary['p99_ns'])}" if "p99_ns" in summary else "")
            )
            diagnostic = details["diagnostics"]
            if diagnostic is not None:
                lag = diagnostic["lag1_correlation"]
                lines.append(
                    f"    descriptive serial lag-1 r={'n/a' if lag is None else f'{lag:.4g}'}; "
                    f"last-minus-first half mean {_ms(diagnostic['last_minus_first_half'])}"
                )
        comparison = workload["comparison"]
        if comparison is not None:
            lines.append(
                f"  Paired candidate/baseline: {comparison['candidate_over_baseline']:.6g} "
                f"({comparison['percent_change']:+.3g}%), CI {_ci(comparison['ratio_ci'])}; "
                f"n={comparison['n_pairs']}"
            )
            lines.append(
                f"  Paired mean candidate-minus-baseline: {_ms(comparison['mean_difference_ns'])}, "
                f"CI {_ci(comparison['difference_ci_ns'], milliseconds=True)}"
            )
        for failure in workload["failures"]:
            lines.append(
                f"  FAILURE {failure['phase']} block={failure['block']} "
                f"{failure['target']} {failure['status']}: {failure['error'] or '(no error text)'}"
            )
        lines.extend(f"  WARNING: {warning}" for warning in workload["warnings"])
    lines.append(
        "\nNo aggregate score; smaller ratios mean faster. Failure to measure is not 'no regression'."
    )
    return "\n".join(lines)
