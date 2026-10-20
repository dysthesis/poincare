"""Human-facing benchmark progress, refreshed only at untimed boundaries.

There is deliberately no worker, timer, or automatic refresh. Call ``recorded``
only after the observation's journal append, flush, and fsync have returned.
"""

from __future__ import annotations

import importlib
import json
import os
import re
import sys
import time
import unicodedata
from importlib import metadata
from pathlib import Path
from typing import Any, TextIO

VERSION = "poincare-benchmark-progress/v1"

_WORKLOAD_LABELS = {
    "startup-empty": "Empty editor startup",
    "startup-file": "Lua file startup",
    "open-python": "Open Python file",
    "open-rust": "Open Rust file",
    "open-nix": "Open Nix file",
    "open-large": "Open large Python file",
    "edit-insert": "Insert paired delimiters",
    "edit-paste-undo": "Paste and undo",
    "treesitter-motion": "Move to next function",
    "folds": "Close code folds",
    "scroll": "Scroll highlighted code",
    "buffer-switch": "Switch buffers",
    "split-resize": "Resize and select split",
    "completion-buffer": "Buffer completion",
    "picker-files-first": "First file search",
    "picker-files-repeat": "Repeated file search",
    "picker-grep": "Search file contents",
    "git-gutter": "Git change markers",
    "git-blame": "Git blame annotation",
    "pins-select": "Select pinned file",
    "format-save-lua": "Format and save Lua",
    "lint-lua": "Lint Lua on save",
    "lsp-lua-ready": "Lua language server readiness",
    "lsp-definition": "Go to Lua definition",
    "completion-lsp": "Language server completion",
    "redraw-control": "Diagnostic redraw",
}


def literal(value: Any) -> str:
    """Keep evidence literal, including terminal controls and bidi formatting."""
    output = []
    for character in str(value):
        if unicodedata.category(character) in ("Cc", "Cf", "Cs", "Zl", "Zp"):
            codepoint = ord(character)
            output.append(
                f"\\x{codepoint:02x}" if codepoint <= 0xFF else f"\\u{codepoint:04x}"
            )
        else:
            output.append(character)
    return "".join(output)


def workload_label(name: str) -> str:
    return _WORKLOAD_LABELS.get(name, literal(name).replace("-", " "))


def preparation_activity(name: str) -> str:
    if name == "completion-lsp":
        return "Waiting for language server and workspace indexing"
    if name == "lsp-definition":
        return "Waiting for language server"
    return "Preparing editor interaction"


def _error_summary(error: Any) -> str:
    reason = str(error or "No error reason was recorded")
    payload = reason.find("{")
    if payload >= 0:
        try:
            evidence, _ = json.JSONDecoder().raw_decode(reason[payload:])
        except ValueError:
            pass
        else:
            if isinstance(evidence, dict):
                context = reason[:payload].rstrip(": ")
                if "preparation " in context:
                    context = "Editor preparation"
                message = evidence.get("error") or evidence.get("message")
                reason = (
                    f"{context}: {message}"
                    if isinstance(message, str)
                    else f"{context}: readiness check failed; see full evidence"
                )
    # RPC failures may contain a repr-escaped Lua traceback on one Python line.
    reason = reason.replace(r"\n", "\n").split("stack traceback:", 1)[0]
    lines = [line.strip() for line in reason.splitlines()]
    meaningful = [
        line
        for line in lines
        if line
        and not line.startswith(("Traceback", "File ", "stack traceback:", "[C]:"))
        and "in function" not in line
    ]
    causes = [
        line
        for line in meaningful
        if any(
            phrase in line.lower()
            for phrase in (
                "missing",
                "not found",
                "required",
                "requires",
                "timed out",
                "unavailable",
            )
        )
    ]
    summary = " / ".join((causes or meaningful or lines)[-2:])
    # Discard our RPC/Lua wrapper in the summary, never in retained evidence.
    summary = re.sub(r"^Acquisition(?:Error|Timeout):\s*", "", summary)
    summary = re.sub(r"^nvim_[A-Za-z0-9_]+:\s*", "", summary)
    rpc_payload = re.match(r"""^\[\s*-?\d+\s*,\s*(["'])(.*)""", summary)
    if rpc_payload:
        summary = rpc_payload[2].removesuffix(f"{rpc_payload[1]}]")
    if summary.startswith("Lua:"):
        summary = summary.removeprefix("Lua:").lstrip()
        summary = re.sub(r"^.*?:\d+(?::\d+)?:\s*", "", summary, count=1)
    summary = summary.replace("semantic oracle", "readiness check").replace(
        "oracle", "readiness check"
    )
    for name, label in _WORKLOAD_LABELS.items():
        summary = summary.replace(f"{name}:", f"{label}:")
    summary = literal(summary)
    return summary if len(summary) <= 280 else "..." + summary[-277:]


def _duration(seconds: float) -> str:
    seconds = max(0, round(seconds))
    if seconds < 60:
        return f"{seconds}s"
    minutes, seconds = divmod(seconds, 60)
    if minutes < 60:
        return f"{minutes}m {seconds:02d}s"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h {minutes:02d}m"


class BenchmarkProgress:
    """Compact stderr Live display, or bounded plain logs on other streams."""

    def __init__(
        self, *, enabled: bool = True, plain: bool = False, file: TextIO | None = None
    ) -> None:
        self.enabled = enabled
        self.plain = plain
        self.file = sys.stderr if file is None else file
        self.mode = "disabled" if not enabled else "plain"
        self.rich_version: str | None = None
        self.total: int | None = None
        self.completed = 0
        self.successful = 0
        self.failed = 0
        self.timeouts = 0
        self._repeat = 0
        self._warmups = 0
        self._started = 0.0
        self._collection_started: float | None = None
        self._collecting = False
        self._activity = "Starting"
        self._item: dict[str, Any] | None = None
        self._phase: str | None = None
        self._milestone = 0
        self._journal: Path | None = None
        self._finished = False
        self._stopped = False
        self._live: Any = None
        self._console: Any = None
        self._text: Any = None
        self._group: Any = None
        self._bar: Any = None
        self._table: Any = None

    def __enter__(self) -> BenchmarkProgress:
        self._started = time.monotonic()
        if (
            not self.enabled
            or self.plain
            or not self.file.isatty()
            or os.environ.get("TERM", "unknown").lower() in ("", "dumb", "unknown")
        ):
            return self
        try:
            console = importlib.import_module("rich.console")
            live = importlib.import_module("rich.live")
            self._text = importlib.import_module("rich.text").Text
            self._group = console.Group
            self._bar = importlib.import_module("rich.progress_bar").ProgressBar
            self._table = importlib.import_module("rich.table").Table
        except ImportError:
            return self
        try:
            self.rich_version = metadata.version("rich")
        except metadata.PackageNotFoundError:
            pass
        self._console = console.Console(
            file=self.file,
            markup=False,
            highlight=False,
            emoji=False,
            no_color="NO_COLOR" in os.environ,
        )
        self._console.width = min(120, self._console.width)
        self._live = live.Live(
            self._render(),
            console=self._console,
            auto_refresh=False,
            redirect_stdout=False,
            redirect_stderr=False,
        )
        self.mode = "rich"
        try:
            self._live.start(refresh=False)
        except BaseException:
            self._live.stop()
            self._live = None
            raise
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        self.finish(complete=False)

    def policy(self) -> dict[str, Any]:
        return {
            "version": VERSION,
            "mode": self.mode,
            "stream": "stderr",
            "rich_version": self.rich_version,
            "refresh": "manual, at untimed boundaries only; no worker or timer",
            "measurement_isolation": "no display callbacks or writes between timer_start and the qualifying redraw flush, or inside RPC/readiness polling",
            "counting": "all scheduled warmups and measured attempts; retained counts advance only after journal flush and fsync return",
            "plain_logging": "stages, phase changes, at most ten coarse count milestones, and every failure",
            "observer_effect": "terminal work is outside scored intervals but may still affect host state; zero observer effect is not claimed",
        }

    def configure(self, *, total: int, repeat: int, warmups: int) -> None:
        self.total = total
        self._repeat = repeat
        self._warmups = warmups
        self._refresh()

    def journal_created(self, path: Path) -> None:
        self._journal = path

    def stage(self, activity: str) -> None:
        self._activity = literal(activity)
        self._item = None
        self._collecting = False
        self._refresh()
        if self.enabled and self._live is None:
            self._log(self._activity)

    def begin(self, item: dict[str, Any]) -> None:
        self._item = item
        self._activity = "Preparing fixtures"
        self._collecting = True
        if self._collection_started is None:
            self._collection_started = time.monotonic()
        self._refresh()
        if item["phase"] != self._phase:
            self._phase = item["phase"]
            if self.enabled and self._live is None:
                phase = "Warmups" if self._phase == "warmup" else "Measured runs"
                self._log(f"{phase} started: {self._context()}")

    def status(self, activity: str) -> None:
        """Update at an untimed boundary; never call this from a polling loop."""
        self._activity = literal(activity)
        self._refresh()

    def recorded(self, observation: dict[str, Any]) -> None:
        """Account for one attempt only AFTER its journal fsync has returned."""
        self.completed += 1
        failed = observation["status"] != "ok"
        self.failed += int(failed)
        self.successful += int(not failed)
        self.timeouts += int(observation["status"] == "timeout")
        self._activity = "Saved failed attempt" if failed else "Saved observation"
        self._refresh()
        milestone = self.completed * 10 // self.total if self.total else 0
        if self.enabled:
            if failed:
                result = "Timed out" if observation["status"] == "timeout" else "Failed"
                self._log(
                    f"{result}: {self._context(observation)} — "
                    f"{_error_summary(observation.get('error'))} "
                    "(full evidence: --details or JSON)"
                )
            elif self._live is None and milestone > self._milestone:
                self._log(f"{self._counts()} · {self._context()}")
        self._milestone = milestone

    def finish(self, *, complete: bool) -> None:
        if self._finished:
            return
        self._finished = True
        self._stopped = not complete
        self._collecting = False
        self._item = None
        self._activity = (
            "Finished with failed attempts"
            if complete and self.failed
            else "Finished" if complete else "Stopped — partial run"
        )
        live, self._live = self._live, None
        try:
            if live is not None:
                live.update(self._render(), refresh=False)
            elif self.enabled:
                self._log(
                    f"{self._activity}: {self._counts()} · "
                    f"Elapsed {_duration(time.monotonic() - self._started)}"
                )
        finally:
            if live is not None:
                live.stop()
        if self.enabled and self._journal is not None:
            self._log(f"Journal: {literal(self._journal)}")

    def _context(self, item: dict[str, Any] | None = None) -> str:
        item = self._item if item is None else item
        if item is None:
            if self.total is None:
                return "Warmups and measured runs will both be counted"
            return (
                f"{self._warmups} warmup{'s' if self._warmups != 1 else ''} + "
                f"{self._repeat} measured run{'s' if self._repeat != 1 else ''} "
                "per workload and target"
            )
        warmup = item["phase"] == "warmup"
        count = self._warmups if warmup else self._repeat
        phase = "Warmup" if warmup else "Run"
        target = {"baseline": "Baseline", "candidate": "Candidate"}.get(
            item["target"], literal(item["target"])
        )
        return (
            f"{workload_label(item['workload'])} · {target} · "
            f"{phase} {item['block'] + 1}/{count}"
        )

    def _counts(self) -> str:
        count = (
            str(self.completed)
            if self.total is None
            else f"{self.completed}/{self.total}"
        )
        timeouts = f" ({self.timeouts} timed out)" if self.timeouts else ""
        return (
            f"{count} saved attempt{'s' if self.completed != 1 else ''} · "
            f"{self.successful} successful · {self.failed} failed{timeouts}"
        )

    def _render(self) -> Any:
        tone = (
            "yellow"
            if self._stopped
            else "red" if self.failed else "green" if self._finished else "cyan"
        )
        counts = self._text(self._counts())
        count_row: Any = counts
        if self.total:
            counts = self._text(
                f"{self.completed}/{self.total} saved · {self.successful} OK · "
            )
            counts.append(
                f"{self.failed} failed", style="bold red" if self.failed else "dim"
            )
            if self.timeouts:
                counts.append(f" ({self.timeouts} timed out)", style="red")
            bar_width = max(
                4,
                min(
                    24,
                    self._console.width // 4,
                    self._console.width - counts.cell_len - 1,
                ),
            )
            count_row = self._table.grid(padding=(0, 1), expand=False)
            count_row.add_column(width=bar_width, no_wrap=True)
            count_row.add_column()
            count_row.add_row(
                self._bar(
                    total=self.total,
                    completed=self.completed,
                    width=bar_width,
                    style="bright_black",
                    complete_style=tone,
                    finished_style=tone,
                    pulse=False,
                ),
                counts,
            )
        remaining = "not estimated"
        if (
            self._collecting
            and self._collection_started is not None
            and self.total is not None
            and 0 < self.completed < self.total
        ):
            remaining = _duration(
                (time.monotonic() - self._collection_started)
                * (self.total - self.completed)
                / self.completed
            )
        return self._group(
            self._text(f"Neovim benchmark · {self._activity}", style=f"bold {tone}"),
            self._text(self._context()),
            count_row,
            self._text(
                f"Elapsed {_duration(time.monotonic() - self._started)} · Approx. remaining: {remaining}",
                style="dim",
            ),
        )

    def _refresh(self) -> None:
        if self._live is not None:
            self._live.update(self._render(), refresh=True)

    def _log(self, message: str) -> None:
        if self._live is not None:
            self._console.print(self._text(message), markup=False, highlight=False)
        else:
            print(message, file=self.file, flush=True)
