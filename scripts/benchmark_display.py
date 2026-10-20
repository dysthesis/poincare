"""Human-first benchmark reports; Rich is optional and imported only for a TTY."""

from __future__ import annotations

import importlib
import json
import os
import re
import shutil
import sys
import unicodedata
from collections import Counter
from typing import TextIO

MAX_WIDTH = 120
TABLE_MIN_WIDTH = 100

# These engine warnings have shorter, consolidated explanations below. Unknown
# warnings are still shown, so adding an engine warning cannot silently hide it.
_CONSOLIDATED_WARNINGS = (
    "Inadequate adjusted-tail bootstrap support:",
    "Block length equals n:",
    "Errors/timeouts in either phase invalidate this entire workload.",
    "Underresolved bootstrap tails (",
    "Full-length circular blocks provide no uncertainty estimate;",
    "Small-sample median intervals are exploratory.",
    "p95 is low-support below 100 measured processes;",
)


def _safe(value: object) -> str:
    """Keep evidence literal, including terminal controls and bidi formatting."""
    result = []
    for character in str(value):
        if unicodedata.category(character) in {"Cc", "Cf", "Cs", "Zl", "Zp"}:
            code = ord(character)
            if character in "\n\r\t":
                result.append({"\n": r"\n", "\r": r"\r", "\t": r"\t"}[character])
            elif code <= 0xFF:
                result.append(f"\\x{code:02x}")
            elif code <= 0xFFFF:
                result.append(f"\\u{code:04x}")
            else:
                result.append(f"\\U{code:08x}")
        else:
            result.append(character)
    return "".join(result)


def _cells(text: str) -> int:
    return sum(
        (
            0
            if unicodedata.combining(character)
            else 2 if unicodedata.east_asian_width(character) in {"W", "F"} else 1
        )
        for character in text
    )


def _wrap(text: str, width: int) -> list[str]:
    """Wrap without dropping any part of a name, interval, or error reason."""
    lines = []
    line = ""
    for word in text.split():
        if line and _cells(line) + 1 + _cells(word) <= width:
            line += " " + word
            continue
        if line:
            lines.append(line)
            line = ""
        for character in word:
            if line and _cells(line + character) > width:
                lines.append(line)
                line = ""
            line += character
    if line or not lines:
        lines.append(line)
    return lines


def _width(file: TextIO, width: int | None) -> int:
    if width is None:
        try:
            width = os.get_terminal_size(file.fileno()).columns
        except (AttributeError, OSError, ValueError):
            width = shutil.get_terminal_size((100, 24)).columns
    return max(1, min(MAX_WIDTH, width))


def _console(file: TextIO, width: int, plain: bool) -> object | None:
    if plain or not getattr(file, "isatty", lambda: False)():
        return None
    if os.environ.get("TERM", "").lower() in {"", "dumb", "unknown"}:
        return None
    try:
        from rich.console import Console
    except ImportError:
        return None
    return Console(
        file=file,
        width=width,
        markup=False,
        emoji=False,
        highlight=False,
        no_color="NO_COLOR" in os.environ,
        color_system=None if "NO_COLOR" in os.environ else "auto",
    )


class _Printer:
    def __init__(self, file: TextIO, width: int, console: object | None) -> None:
        self.file = file
        self.width = width
        self.console = console

    def line(self, text: object = "", *, style: str = "") -> None:
        literal = _safe(text)
        if self.console is not None:
            from rich.text import Text

            self.console.print(Text(literal, style=style), overflow="fold")
        else:
            for line in _wrap(literal, self.width):
                print(line, file=self.file)

    def table(
        self,
        headers: tuple[str, ...],
        rows: list[tuple[str, ...]],
        *,
        cell_styles: dict[tuple[int, int], str] | None = None,
    ) -> None:
        headers = tuple(_safe(value) for value in headers)
        rows = [tuple(_safe(value) for value in row) for row in rows]
        if self.console is not None:
            from rich import box
            from rich.table import Table
            from rich.text import Text

            table = Table(box=box.SIMPLE_HEAD, padding=(0, 1), expand=True)
            for header in headers:
                table.add_column(Text(header), overflow="fold")
            for row_index, row in enumerate(rows):
                table.add_row(
                    *(
                        Text(
                            value,
                            style=(
                                cell_styles.get((row_index, column), "")
                                if cell_styles
                                else ""
                            ),
                        )
                        for column, value in enumerate(row)
                    )
                )
            self.console.print(table)
            return
        widths = [
            max(_cells(row[index]) for row in [headers, *rows])
            for index in range(len(headers))
        ]
        available = self.width - 2 * (len(headers) - 1)
        while sum(widths) > available and max(widths) > 1:
            largest = max(range(len(widths)), key=widths.__getitem__)
            widths[largest] -= 1
        for row in [headers, tuple("-" * width for width in widths), *rows]:
            wrapped = [_wrap(value, width) for value, width in zip(row, widths)]
            for index in range(max(map(len, wrapped))):
                cells = [
                    column[index] if index < len(column) else "" for column in wrapped
                ]
                print(
                    "  ".join(
                        value + " " * (width - _cells(value))
                        for value, width in zip(cells, widths)
                    ).rstrip(),
                    file=self.file,
                )


def _unit(values: list[float | None]) -> tuple[float, str]:
    largest = max((abs(value) for value in values if value is not None), default=0)
    if largest >= 1_000_000_000:
        return 1_000_000_000, "s"
    if largest >= 1_000_000:
        return 1_000_000, "ms"
    if largest >= 1_000:
        return 1_000, "µs"
    return 1, "ns"


def _time(value: float | None, *, digits: int = 4) -> str:
    if value is None:
        return "unavailable"
    divisor, unit = _unit([value])
    return f"{value / divisor:.{digits}g} {unit}"


def _interval(
    values: list[float] | None, *, time: bool = False, digits: int = 4
) -> str:
    if values is None:
        return "unavailable"
    divisor, unit = _unit(values) if time else (1, "")
    return (
        f"[{values[0] / divisor:.{digits}g}, "
        f"{values[1] / divisor:.{digits}g}]" + (f" {unit}" if unit else "")
    )


def _median(target: dict, divisor: float) -> str:
    median = target["descriptive"]["median_ns"]
    interval = target["median_ci_ns"]
    if median is None:
        return "unavailable"
    if interval is None:
        return f"{median / divisor:.4g} [CI unavailable]"
    return (
        f"{median / divisor:.4g} "
        f"[{interval[0] / divisor:.4g}, {interval[1] / divisor:.4g}]"
    )


def _change(comparison: dict | None) -> str:
    if comparison is None:
        return "unavailable"
    point = f"{comparison['percent_change']:+.3g}%"
    interval = comparison["ratio_ci"]
    if interval is None:
        return f"{point} [CI unavailable]"
    return (
        f"{point} [{(interval[0] - 1) * 100:+.3g}%, "
        f"{(interval[1] - 1) * 100:+.3g}%]"
    )


def _verdict(workload: dict, report: dict) -> str:
    return {
        "regression": "Slower",
        "improvement": "Faster",
        "within practical band": f"Within ±{report['statistics']['practical'] * 100:.3g}%",
        "inconclusive": "Uncertain",
        "exploratory": "Not enough evidence",
        "invalid": "Failed",
        "descriptive": "Descriptive only",
    }.get(workload["decision"], _safe(workload["decision"]))


def _verdict_style(workload: dict) -> str:
    return {
        "regression": "bold red",
        "improvement": "bold green",
        "within practical band": "bold cyan",
        "inconclusive": "bold yellow",
        "exploratory": "bold yellow",
        "invalid": "bold red",
    }.get(workload["decision"], "bold")


def _header(report: dict, printer: _Printer) -> None:
    failures = sum(len(workload["failures"]) for workload in report["workloads"])
    status = "Completed"
    if failures:
        status += f" with {failures} failed observation{'s' if failures != 1 else ''}"
    printer.line(f"Neovim benchmark — {status}", style="bold")
    state = report.get("metadata", {}).get(
        "state_policy", report.get("metadata", {}).get("state", "not recorded")
    )
    state_label = f"{state} state" if state in ("warm", "fresh") else f"state: {state}"
    printer.line(
        f"{report['repeat']} run{'s' if report['repeat'] != 1 else ''} + "
        f"{report['warmups']} warmup{'s' if report['warmups'] != 1 else ''} each · "
        f"{' vs '.join(report['targets'])} · {state_label}",
        style="dim",
    )


def _overview(report: dict, printer: _Printer) -> None:
    paired = "baseline" in report["targets"]
    times = []
    for workload in report["workloads"]:
        if workload["valid"]:
            for target in workload["targets"].values():
                times.append(target["descriptive"]["median_ns"])
                if not paired:
                    times.append(target["descriptive"]["p95_ns"])
                    times.extend(target["median_ci_ns"] or [])
    divisor, unit = _unit(times) if times else (1_000_000, "ms")
    if paired:
        headers = (
            "Workload",
            f"Baseline median ({unit})",
            f"Candidate median ({unit})",
            "Paired change % [CI]",
            "Verdict",
        )
        rows = [
            (
                workload["name"],
                (
                    f"{workload['targets']['baseline']['descriptive']['median_ns'] / divisor:.4g}"
                    if workload["valid"]
                    else "unavailable"
                ),
                (
                    f"{workload['targets']['candidate']['descriptive']['median_ns'] / divisor:.4g}"
                    if workload["valid"]
                    else "unavailable"
                ),
                _change(workload["comparison"]),
                _verdict(workload, report),
            )
            for workload in report["workloads"]
        ]
    else:
        headers = (
            "Workload",
            f"Median [CI] ({unit})",
            f"p95 ({unit})",
            "Runs ok/planned",
        )
        rows = []
        for workload in report["workloads"]:
            target = workload["targets"][report["targets"][0]]
            summary = target["descriptive"]
            rows.append(
                (
                    workload["name"] + (" — Failed" if not workload["valid"] else ""),
                    _median(target, divisor) if workload["valid"] else "unavailable",
                    (
                        (
                            f"{summary['p95_ns'] / divisor:.4g}"
                            + ("*" if summary["p95_low_support"] else "")
                        )
                        if workload["valid"]
                        else "unavailable"
                    ),
                    f"{target['counts']['measure']['ok']}/{report['repeat']}",
                )
            )
    if printer.width >= TABLE_MIN_WIDTH:
        printer.table(
            headers,
            rows,
            cell_styles={
                (index, 4 if paired else 0): _verdict_style(workload)
                for index, workload in enumerate(report["workloads"])
                if paired or not workload["valid"]
            },
        )
    else:
        for index, row in enumerate(rows):
            if index:
                printer.line()
            if paired:
                printer.line(
                    f"{row[0]} — {row[4]}",
                    style=_verdict_style(report["workloads"][index]),
                )
                printer.line(f"Medians ({unit}): baseline {row[1]}; candidate {row[2]}")
                printer.line(f"Paired change % [CI]: {row[3]}")
            else:
                printer.line(row[0], style=_verdict_style(report["workloads"][index]))
                printer.line(f"Median [CI] ({unit}): {row[1]}")
                printer.line(f"p95 ({unit}): {row[2]}; measured ok/planned: {row[3]}")


def _provenance(report: dict) -> list[str]:
    provenance = report.get("analysis_overrides")
    if provenance is None:
        return []
    notes = []
    if provenance["overrides"]:
        changed = ", ".join(
            f"{_safe(name)}={_safe(value)}"
            for name, value in sorted(provenance["overrides"].items())
        )
        notes.append(f"SENSITIVITY OVERRIDES: {changed} (explicit replay settings).")
    if provenance["stored_plan"] is None:
        notes.append(
            "No recorded pre-acquisition analysis plan; replay settings were not predeclared."
        )
    return notes


def _risk_notes(report: dict) -> list[str]:
    settings = report["statistics"]
    paired = "baseline" in report["targets"]
    valid = any(workload["valid"] for workload in report["workloads"])
    notes = _provenance(report)
    if valid and not settings["intervals_available"]:
        action = (
            "Collect more measured runs and choose --block-length below --repeat"
            if report["repeat"] < 2
            else "Choose --block-length below --repeat"
        )
        notes.append(
            f"No uncertainty intervals: block length equals the run count. {action}; "
            "more --resamples cannot restore variation."
        )
    elif valid and not settings["adequate_tail_support"]:
        notes.append(
            f"Bootstrap tails underresolved: {settings['expected_resamples_per_tail']:.3g} "
            f"expected resamples/tail; need at least {settings['recommended_resamples_per_tail']}. "
            "Increase --resamples; retained intervals are exploratory."
        )
    if valid and report["repeat"] < settings["minimum_pairs"]:
        unit = "pair" if paired else "run"
        if report["repeat"] != 1:
            unit += "s"
        support = (
            f"paired verdicts need at least {settings['minimum_pairs']}. "
            if paired
            else (
                "median intervals are exploratory. "
                if settings["intervals_available"]
                else ""
            )
        )
        notes.append(
            f"Only {report['repeat']} measured {unit}; {support}"
            "Increase --repeat for more measured observations."
        )
    if not paired and any(
        workload["valid"]
        and workload["targets"][report["targets"][0]]["descriptive"]["p95_low_support"]
        for workload in report["workloads"]
    ):
        notes.append(
            "* p95 has low support below 100 successful runs; more measured runs, "
            "not more resamples, improve tail support."
        )
    extras: dict[str, list[str]] = {}
    for warning in report["warnings"]:
        if not warning.startswith(_CONSOLIDATED_WARNINGS):
            extras.setdefault(warning, [])
    for workload in report["workloads"]:
        for warning in workload["warnings"]:
            if warning.startswith(_CONSOLIDATED_WARNINGS) or warning.startswith(
                f"Only {report['repeat']} measured pairs;"
            ):
                continue
            extras.setdefault(warning, []).append(workload["name"])
    for warning, names in extras.items():
        notes.append((", ".join(names) + ": " if names else "") + warning)
    return notes


def _error_summary(error: str | None) -> str:
    if not error:
        return "no error text recorded"
    # Oracle errors may be JSON, RPC errors Python repr, or ordinary traceback
    # text. Summaries unwrap the useful error, not the large evidence dictionary.
    start = error.find("{")
    if start >= 0:
        try:
            evidence = json.loads(error[start:])
        except (ValueError, TypeError):
            pass
        else:
            if isinstance(evidence, dict) and isinstance(evidence.get("error"), str):
                error = evidence["error"]
    lines = []
    for line in error.replace(r"\n", "\n").splitlines():
        line = line.strip()
        if line.startswith("stack traceback:"):
            break
        if line and not line.startswith(("Traceback (", 'File "', "^")):
            lines.append(line)
    summary = lines[0] if lines else error
    if len(lines) > 1 and lines[-1] != lines[0]:
        summary += "; " + lines[-1]
    # Strip our transport envelope and Lua source location in the summary only.
    summary = re.sub(r"^Acquisition(?:Error|Timeout):\s*", "", summary)
    summary = re.sub(r"^nvim_[A-Za-z0-9_]+:\s*", "", summary)
    rpc_payload = re.match(r"""^\[\s*-?\d+\s*,\s*(["'])(.*)""", summary)
    if rpc_payload:
        summary = rpc_payload[2].removesuffix(f"{rpc_payload[1]}]")
    if summary.startswith("Lua:"):
        summary = summary.removeprefix("Lua:").lstrip()
        summary = re.sub(r"^.*?:\d+(?::\d+)?:\s*", "", summary, count=1)
    summary = _safe(summary)
    if len(summary) > 220:
        summary = summary[:100] + " … " + summary[-110:]
    return summary


def _failure_notes(report: dict, printer: _Printer) -> None:
    groups: Counter[tuple[str, ...]] = Counter()
    total = 0
    for workload in report["workloads"]:
        for failure in workload["failures"]:
            total += 1
            groups[
                (
                    workload["name"],
                    failure["target"],
                    failure["phase"],
                    failure["status"],
                    _error_summary(failure["error"]),
                )
            ] += 1
    if not total:
        return
    shown = min(3, len(groups))
    printer.line(
        f"Failures: {total} total; {shown}/{len(groups)} grouped reasons below. "
        "Full errors and traces: --details or --json.",
        style="bold red",
    )
    for (name, target, phase, status, reason), count in list(groups.items())[:shown]:
        printer.line(f"{name} / {target} / {phase}: {count} {status}; {reason}")


def _summary(report: dict, printer: _Printer) -> None:
    _header(report, printer)
    printer.line()
    _overview(report, printer)
    printer.line()
    for note in _risk_notes(report):
        printer.line(note, style="yellow")
    _failure_notes(report, printer)
    settings = report["statistics"]
    if "baseline" in report["targets"]:
        printer.line(
            "% change compares paired runs, not displayed medians; negative is faster.",
            style="dim",
        )
    printer.line(
        f"Approximate intervals: {settings['confidence'] * 100:.3g}% family target, "
        f"adjusted across {settings['family_size']} workload{'s' if settings['family_size'] != 1 else ''}"
        + (
            f"; practical band ±{settings['practical'] * 100:.3g}%."
            if "baseline" in report["targets"]
            else "."
        ),
        style="dim",
    )
    printer.line(
        "Checked forced-redraw interval includes harness work, not physical display latency.",
        style="dim",
    )
    printer.line("Full statistics: --details.", style="dim")


def _literal_report(report: dict) -> dict:
    """Project only fields used by the legacy details renderer, never rich evidence."""
    result = {key: report[key] for key in ("valid", "repeat", "warmups", "targets")}
    result["statistics"] = {
        key: _safe(value) if isinstance(value, str) else value
        for key, value in report["statistics"].items()
    }
    result["warnings"] = [_safe(warning) for warning in report["warnings"]]
    if "analysis_overrides" in report:
        provenance = report["analysis_overrides"]
        result["analysis_overrides"] = {
            "stored_plan": provenance["stored_plan"],
            "overrides": {_safe(key): None for key in provenance["overrides"]},
        }
    result["workloads"] = []
    for workload in report["workloads"]:
        result["workloads"].append(
            {
                "name": _safe(workload["name"]),
                "decision": _safe(workload["decision"]),
                "targets": {
                    _safe(name): target for name, target in workload["targets"].items()
                },
                "comparison": workload["comparison"],
                "warnings": [_safe(warning) for warning in workload["warnings"]],
                "failures": [
                    {
                        key: _safe(failure[key])
                        for key in ("phase", "block", "target", "status", "error")
                    }
                    for failure in workload["failures"]
                ],
            }
        )
    return result


def _traces(report: dict, printer: _Printer) -> None:
    for workload in report["workloads"]:
        for failure in workload["failures"]:
            trace = failure.get("exception_traceback")
            if trace:
                printer.line(
                    f"Trace: {workload['name']} / {failure['target']} / "
                    f"{failure['phase']} block {failure['block']}",
                    style="bold red",
                )
                for line in trace.split("\n"):
                    printer.line(line)


def _plain_details(report: dict, printer: _Printer) -> None:
    statistics = (
        importlib.import_module(".benchmark_stats", __package__)
        if __package__
        else importlib.import_module("benchmark_stats")
    )
    for line in statistics.render(_literal_report(report)).splitlines():
        printer.line(line)
    _traces(report, printer)
    printer.line(
        "Checked forced-redraw interval includes harness work, not physical display latency."
    )


def _counts(counts: dict) -> str:
    return (
        f"{counts['ok']}/{counts['total']} ok; "
        f"{counts['error']} errors, {counts['timeout']} timeouts"
    )


def _rich_details(report: dict, printer: _Printer) -> None:
    _header(report, printer)
    settings = report["statistics"]
    printer.line("Analysis plan and uncertainty", style="bold")
    printer.table(
        ("Setting", "Value"),
        [
            ("Bootstrap", settings["method"]),
            (
                "Resamples",
                f"{settings['resamples']} requested; {settings['resamples_per_valid_workload']} per valid workload",
            ),
            (
                "Block length",
                f"{settings['block_length']} ({settings['block_length_policy']})",
            ),
            ("Analysis seed", str(settings["seed"])),
            ("Primary endpoint", settings["primary_endpoint"]),
            (
                "Confidence",
                f"{settings['confidence'] * 100:.6g}% nominal family; {settings['interval_confidence'] * 100:.6g}% per workload",
            ),
            (
                "Family",
                f"{settings['family_size']} workload{'s' if settings['family_size'] != 1 else ''}, including invalid workloads",
            ),
            (
                "Adjusted-tail support",
                f"{settings['expected_resamples_per_tail']:.6g} expected resamples/tail; at least {settings['recommended_resamples_per_tail']} required",
            ),
            (
                "Practical ratio band",
                _interval(
                    [1 - settings["practical"], 1 + settings["practical"]], digits=6
                ),
            ),
            ("Secondary intervals", settings["secondary_interval_scope"]),
        ],
    )
    for note in _provenance(report):
        printer.line(note, style="bold yellow")
    printer.line(
        "Intervals are approximate and conditional on this host, fixture, state, "
        "and short-range dependence model.",
        style="dim",
    )
    for warning in report["warnings"]:
        printer.line(f"Warning: {warning}", style="yellow")
    for workload in report["workloads"]:
        printer.line()
        printer.line(
            f"{workload['name']} — {_verdict(workload, report)}",
            style=_verdict_style(workload),
        )
        targets = list(workload["targets"].items())
        rows = [
            (
                "Measured",
                *(_counts(target["counts"]["measure"]) for _, target in targets),
            ),
            (
                "Warmups",
                *(_counts(target["counts"]["warmup"]) for _, target in targets),
            ),
        ]
        for label, key in (
            ("Mean", "mean_ns"),
            ("Median", "median_ns"),
            ("Sample SD", "sd_ns"),
            ("MAD", "mad_ns"),
            ("Minimum", "min_ns"),
            ("Maximum", "max_ns"),
            ("p90", "p90_ns"),
            ("p95", "p95_ns"),
            ("p99", "p99_ns"),
        ):
            if key == "p99_ns" and not any(
                key in target["descriptive"] for _, target in targets
            ):
                continue
            rows.append(
                (
                    label,
                    *(
                        _time(target["descriptive"].get(key), digits=6)
                        + (
                            " (low support)"
                            if target["descriptive"].get(label + "_low_support")
                            else ""
                        )
                        for _, target in targets
                    ),
                )
            )
        rows.append(
            (
                "Median CI",
                *(
                    _interval(target["median_ci_ns"], time=True, digits=6)
                    for _, target in targets
                ),
            )
        )
        for label, key in (
            ("Serial lag-1 r", "lag1_correlation"),
            ("Last-minus-first half mean", "last_minus_first_half"),
        ):
            values = []
            for _, target in targets:
                diagnostic = target["diagnostics"]
                value = diagnostic[key] if diagnostic is not None else None
                values.append(
                    _time(value, digits=6)
                    if key != "lag1_correlation"
                    else (f"{value:.6g}" if value is not None else "unavailable")
                )
            rows.append((label, *values))
        printer.table(("Statistic", *(name for name, _ in targets)), rows)
        if not workload["valid"]:
            printer.line(
                "Successful-only descriptives above; errors in either phase invalidate "
                "the workload. No inferential comparison is available.",
                style="yellow",
            )
        comparison = workload["comparison"]
        if comparison is not None:
            printer.table(
                ("Paired statistic", "Value"),
                [
                    ("Measured pairs", str(comparison["n_pairs"])),
                    (
                        "Geometric mean candidate/baseline",
                        f"{comparison['candidate_over_baseline']:.6g}",
                    ),
                    ("Percent change [adjusted CI]", _change(comparison)),
                    ("Ratio CI", _interval(comparison["ratio_ci"], digits=6)),
                    (
                        "Mean candidate-minus-baseline",
                        _time(comparison["mean_difference_ns"], digits=6),
                    ),
                    (
                        "Difference CI",
                        _interval(comparison["difference_ci_ns"], time=True, digits=6),
                    ),
                ],
            )
            diagnostic_rows = []
            for name, diagnostic in comparison["diagnostics"].items():
                lag = diagnostic["lag1_correlation"]
                drift = diagnostic["last_minus_first_half"]
                diagnostic_rows.append(
                    (
                        name,
                        f"{lag:.6g}" if lag is not None else "unavailable",
                        (
                            _time(drift, digits=6)
                            if diagnostic["units"] == "ns"
                            else (
                                f"{drift:.6g} {diagnostic['units']}"
                                if drift is not None
                                else "unavailable"
                            )
                        ),
                    )
                )
            printer.table(
                ("Paired diagnostic", "Lag-1 r", "Last-minus-first half mean"),
                diagnostic_rows,
            )
        for failure in workload["failures"]:
            printer.line(
                f"Failure: {failure['target']} / {failure['phase']} block {failure['block']} "
                f"({failure['status']})",
                style="bold red",
            )
            for line in (failure["error"] or "no error text recorded").split("\n"):
                printer.line(line)
        for warning in workload["warnings"]:
            printer.line(f"Warning: {warning}", style="yellow")
    _traces(report, printer)
    printer.line(
        "No aggregate score; smaller paired ratios mean faster. Failed measurement "
        "is not evidence of unchanged performance.",
        style="dim",
    )
    printer.line(
        "Checked forced-redraw interval includes harness work, not physical display latency.",
        style="dim",
    )


def print_report(
    report: dict,
    *,
    plain: bool = False,
    details: bool = False,
    file: TextIO | None = None,
    width: int | None = None,
) -> None:
    """Print compact results, or an alternate full statistical report with details.

    Evidence is read without mutation or recursive copies. Redirected output,
    limited terminals, explicit plain mode, and missing Rich all use the same
    concise stdlib presentation. The output stream is resolved at call time.
    """
    file = sys.stdout if file is None else file
    width = _width(file, width)
    printer = _Printer(file, width, _console(file, width, plain))
    if details:
        if printer.console is None:
            _plain_details(report, printer)
        else:
            _rich_details(report, printer)
    else:
        _summary(report, printer)
