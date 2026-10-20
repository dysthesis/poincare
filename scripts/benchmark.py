#!/usr/bin/env python3
"""Workload-first attached-UI process benchmarks for the packaged configuration."""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
from pathlib import Path
from typing import Any, Callable, TextIO

try:
    from scripts import benchmark_progress
    from scripts import benchmark_workloads as workloads
    from scripts import perf, pipeline
    from scripts.benchmark_rpc import (
        AcquisitionError,
        AcquisitionTimeout,
        Nvim,
        kill_process_group,
    )
except ModuleNotFoundError:
    import benchmark_progress
    import benchmark_workloads as workloads
    import perf
    import pipeline
    from benchmark_rpc import (
        AcquisitionError,
        AcquisitionTimeout,
        Nvim,
        kill_process_group,
    )

ROOT = Path(__file__).resolve().parent.parent
HARNESS = Path(__file__).resolve().with_name("benchmark.lua")
FORMAT = "poincare-benchmark/v1"
ANALYSIS_DEFAULTS = {
    "resamples": 20000,
    "confidence": 0.95,
    "practical": 0.05,
    "seed": 20261020,
    "block_length": None,
}

# Startup intentionally does NOT load the full scenario harness. The tiny inline
# observer, API handshake, and UI attach are inclusive costs of this boundary.
STARTUP_OBSERVER = r"""
local ch, token, cfg, timeout = ...
local api, fn = vim.api, vim.fn
local deadline = vim.uv.hrtime() + timeout * 1000000
local function poll()
  local buf = api.nvim_get_current_buf()
  local e = {
    vim_did_enter = vim.v.vim_did_enter, path = api.nvim_buf_get_name(buf),
    filetype = vim.bo.filetype, line_count = api.nvim_buf_line_count(buf),
    statusline = vim.o.statusline, completion = type(_G.MiniCompletion) == 'table',
    pins = package.loaded.pins ~= nil, mode = api.nvim_get_mode().mode,
    errmsg = vim.v.errmsg,
    statusline_loaded = package.loaded['ui.statusline'] ~= nil,
    pin_mapping = not vim.tbl_isempty(fn.maparg(' 1', 'n', false, true)),
    first_line = api.nvim_buf_get_lines(buf, 0, 1, false)[1],
    last_line = api.nvim_buf_get_lines(buf, -2, -1, false)[1],
    highlighter_active = vim.treesitter.highlighter.active[buf] ~= nil,
    foldenable = vim.wo.foldenable, foldmethod = vim.wo.foldmethod,
    foldlevel = vim.wo.foldlevel, foldclosed = fn.foldclosed(4), foldclosedend = fn.foldclosedend(4),
    poll_cadence_ms = 1,
  }
  local ready = e.vim_did_enter == 1 and e.completion and e.pins and e.pin_mapping
    and e.statusline_loaded and e.statusline:find('ui.statusline', 1, true) ~= nil
    and e.mode == 'n' and e.path == cfg.path
  if cfg.path ~= '' then
    ready = ready and e.filetype == cfg.filetype and e.line_count == cfg.line_count
      and e.first_line == cfg.first_line and e.last_line == cfg.last_line and e.highlighter_active
      and e.foldenable and e.foldmethod == 'expr' and e.foldlevel == 0 and e.foldclosed == 4 and e.foldclosedend == 10
  end
  if e.errmsg ~= '' then
    e.success = false
    e.error = 'startup vim.v.errmsg: ' .. e.errmsg
    vim.rpcnotify(ch, 'poincare_benchmark', token, 'error', e)
    vim.cmd('redraw!')
    return
  end
  if ready or vim.uv.hrtime() >= deadline then
    e.success = ready == true
    vim.rpcnotify(ch, 'poincare_benchmark', token, ready and 'ok' or 'timeout', e)
    vim.cmd('redraw!')
  else
    vim.defer_fn(poll, 1)
  end
end
poll()
"""


def make_schedule(
    names: list[str], targets: list[str], repeat: int, warmups: int, seed: int
) -> list[dict[str, Any]]:
    """Persist balanced adjacent pairs before any acquisition; no adaptive runs."""
    rng = random.Random(seed)
    schedule = []
    for phase, count in (("warmup", warmups), ("measure", repeat)):
        orders: dict[str, list[bool]] = {}
        for name in names:
            first_candidate = [False] * (count // 2) + [True] * (count // 2)
            if count % 2:
                first_candidate.append(bool(rng.getrandbits(1)))
            rng.shuffle(first_candidate)
            orders[name] = first_candidate
        for block in range(count):
            order = names[:]
            rng.shuffle(order)
            for name in order:
                target_order = targets[:]
                if len(targets) == 2 and orders[name][block]:
                    target_order.reverse()
                for target in target_order:
                    schedule.append(
                        {
                            "phase": phase,
                            "block": block,
                            "workload": name,
                            "target": target,
                        }
                    )
    return schedule


def isolated_environment(state: Path) -> tuple[dict[str, str], dict[str, Any]]:
    environment = os.environ.copy()
    # Wrapper-selected NVIM_APPNAME is retained in the child: remove inherited
    # overrides so a package wrapper can choose its own default without us
    # substituting a harness application name.
    exact = {
        "TMUX",
        "TMUX_PANE",
        "NVIM",
        "NVIM_APPNAME",
        "NVIM_LISTEN_ADDRESS",
        "NVIM_LOG_FILE",
        "VIM",
        "VIMRUNTIME",
        "VIMINIT",
        "GVIMINIT",
        "EXINIT",
        "MYVIMRC",
        "LUA_PATH",
        "LUA_CPATH",
        "LUA_INIT",
        "DISPLAY",
        "WAYLAND_DISPLAY",
        "XAUTHORITY",
        "DBUS_SESSION_BUS_ADDRESS",
        "SSH_ASKPASS",
        "GIT_ASKPASS",
        "RIPGREP_CONFIG_PATH",
        "FD_OPTIONS",
        "FZF_DEFAULT_COMMAND",
        "FZF_DEFAULT_OPTS",
    }
    removed = sorted(
        key
        for key in environment
        if key in exact
        or key.startswith(
            ("GIT_", "NVIM_", "VIM_", "LUA_INIT_", "LUA_PATH_", "LUA_CPATH_")
        )
    )
    for key in removed:
        environment.pop(key, None)
    paths = {"HOME": state / "home"}
    for kind in ("config", "data", "state", "cache", "runtime"):
        paths[
            f"XDG_{kind.upper()}_HOME" if kind != "runtime" else "XDG_RUNTIME_DIR"
        ] = (state / kind)
    paths["XDG_CONFIG_DIRS"] = state / "config-dirs"
    paths["XDG_DATA_DIRS"] = state / "data-dirs"
    paths["TMPDIR"] = state / "tmp"
    for key, path in paths.items():
        path.mkdir(parents=True, exist_ok=True, mode=0o700)
        environment[key] = str(path)
    environment.update(
        {
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_TERMINAL_PROMPT": "0",
            "NVIM_LOG_FILE": str(state / "nvim.log"),
            "TZ": "UTC",
        }
    )
    return environment, {
        "isolated_paths": {key: str(path) for key, path in paths.items()},
        "removed_inherited_variables": removed,
        "git_user_system_config": "disabled",
        "NVIM_APPNAME": "wrapper chooses default after inherited override removal; actual child value recorded",
        "desktop_clipboard": "desktop/session variables removed; nvim_paste does not use clipboard",
        "path_sha256": hashlib.sha256(environment.get("PATH", "").encode()).hexdigest(),
        "path": environment.get("PATH", ""),
        "TZ": "UTC",
        "inherited_values": {
            key: environment.get(key)
            for key in ("LANG", "LC_ALL", "LC_CTYPE", "TERM", "SHELL")
        },
    }


def executable_details(
    path: Path, environment: dict[str, str] | None = None
) -> dict[str, Any]:
    identity = perf.file_identity(path)
    result: dict[str, Any] = {**identity, "version_command": [str(path), "--version"]}
    process = None
    try:
        process = subprocess.Popen(
            result["version_command"],
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            stdout, stderr = process.communicate(timeout=5)
            result.update(
                {
                    "version_stdout": stdout.decode(errors="replace"),
                    "version_stderr": stderr.decode(errors="replace"),
                    "version_returncode": process.returncode,
                }
            )
        except subprocess.TimeoutExpired:
            result["version_error"] = "--version timed out after 5 seconds"
    except OSError as error:
        result["version_error"] = str(error)
    finally:
        if process is not None:
            # Even successful version commands can leave descendants behind.
            result["version_cleanup"] = kill_process_group(process, grace=0.05)
            for pipe in (process.stdout, process.stderr):
                if pipe is not None:
                    pipe.close()
    return result


def _startup_config(
    root: Path, facts: dict[str, dict[str, Any]], with_file: bool
) -> dict[str, Any]:
    file = (
        facts["lua/representative.lua"]
        if with_file
        else {"count": 1, "first": "", "last": "", "filetype": ""}
    )
    return {
        "path": str(root / "lua/representative.lua") if with_file else "",
        "filetype": file["filetype"],
        "line_count": file["count"],
        "first_line": file["first"],
        "last_line": file["last"],
    }


def _observe(client: Nvim, token: str, oracle: str, timeout: float) -> dict[str, Any]:
    client.lua(
        "PoincareBenchmark.observe(...)", token, oracle, max(1, round(timeout * 1000))
    )
    return client.wait_completion(token, timeout=timeout + 0.5)


def _require_success(completion: dict[str, Any], description: str) -> None:
    if completion["status"] == "timeout":
        raise AcquisitionTimeout(
            f"{description}: semantic oracle timed out: {json.dumps(completion['oracle'], ensure_ascii=False)}"
        )
    if completion["status"] != "ok":
        raise AcquisitionError(
            f"{description}: {json.dumps(completion['oracle'], ensure_ascii=False)}"
        )


def _dispatch_action(
    client: Nvim, action: dict[str, Any], intermediate: list[dict[str, Any]]
) -> None:
    if action["kind"] == "input":
        client.input(action["input"])
    elif action["kind"] == "paste-undo":
        accepted = client.request("nvim_paste", action["text"], True, -1)
        if accepted is not True:
            raise AcquisitionError("nvim_paste rejected the fixed burst")
        checked = client.lua("return {PoincareBenchmark.check('paste-inserted')}")
        intermediate.append(
            {"phase": "paste-inserted", "success": checked[0], "oracle": checked[1]}
        )
        if not checked[0]:
            raise AcquisitionError(
                f"paste intermediate text did not match: {checked[1]}"
            )
        client.input("<Esc>u")
    elif action["kind"] not in ("observe", "control"):
        raise AcquisitionError(f"unknown action kind: {action['kind']}")


def _surface_check(name: str, screen: dict[str, Any]) -> dict[str, Any]:
    grid = screen["grids"].get("1", [])
    rendered = "\n".join(grid)
    if not grid or not rendered.strip():
        raise AcquisitionError(
            "checked redraw produced no rendered ext_linegrid surface"
        )
    expected = {
        "startup-empty": "[No Name]",
        "startup-file": "representative.lua",
        "open-python": "representative.py",
        "open-rust": "representative.rs",
        "open-nix": "representative.nix",
        "open-large": "large.py",
        "edit-insert": "seed (alpha)[beta]{gamma}",
        "folds": "… 7 lines …",
        "completion-buffer": workloads.COMPLETION_WORD,
        "completion-lsp": workloads.LSP_COMPLETION_WORD,
        "picker-files-first": workloads.PICKER_QUERY,
        "picker-files-repeat": workloads.PICKER_QUERY,
        "picker-grep": workloads.GREP_QUERY,
        "git-blame": workloads.AUTHOR,
        "format-save-lua": "format.lua",
        "lint-lua": "lint.lua",
        "lsp-definition": "benchlib.lua",
    }.get(name)
    if expected is not None and expected not in rendered:
        raise AcquisitionError(
            f"semantic oracle passed but expected rendered text {expected!r} was absent"
        )
    return {
        "nonempty": True,
        "required_text": expected,
        "required_text_present": expected is None or expected in rendered,
    }


def acquire(
    item: dict[str, Any],
    nvim: Path,
    state: Path,
    project: Path,
    files: dict[str, str],
    scenario: dict[str, Any],
    args: argparse.Namespace,
    tool_cache: dict[str, dict[str, Any]],
    *,
    status: Callable[[str], None] | None = None,
) -> dict[str, Any]:
    observation: dict[str, Any] = {
        "type": "observation",
        **item,
        "status": "error",
        "latency_ns": None,
        "error": None,
        "started_at_unix_ns": time.time_ns(),
        "state_policy": args.state,
        "process_state": "fresh Neovim and child process group",
        "application_state": (
            "isolated HOME/XDG reused per target+workload"
            if args.state == "warm"
            else "new isolated HOME/XDG per scheduled observation"
        ),
        "filesystem_cache": "uncontrolled/warmed; NOT disk-cold",
        "preparation": [],
        "intermediate": [],
        "command": [str(nvim), "--embed", "-i", "NONE", "-n"],
        "cwd": str(project),
    }
    elapsed_start = time.perf_counter_ns()
    client = None
    timer_start = None
    try:
        if status is not None:
            status("Preparing fixtures")
        environment, policy = isolated_environment(state)
        observation["environment_policy"] = policy
        commit = workloads.restore_project(project, files, environment)
        observation["fixture_commit"] = commit
        observation["fixture_root"] = str(project)
        config = scenario | {
            "root": str(project),
            "commit": commit,
            "author": workloads.AUTHOR,
        }
        startup = item["workload"].startswith("startup-")
        command = [str(nvim), "--embed", "-i", "NONE", "-n"]
        if item["workload"] == "startup-file":
            command.append(str(project / "lua/representative.lua"))
        observation["command"] = command
        observation["cwd"] = str(project)
        if status is not None:
            status(
                "Measuring editor startup (display paused)"
                if startup
                else "Preparing editor"
            )
        observation["spawned_at_unix_ns"] = time.time_ns()
        if startup:
            timer_start = time.perf_counter_ns()
        client = Nvim(command, project, environment, args.prepare_timeout)
        if startup:
            client.operation_deadline = (
                time.monotonic()
                + args.timeout
                - (time.perf_counter_ns() - timer_start) / 1e9
            )
        observation["pid"] = client.process.pid if client.process is not None else None
        channel, api_metadata = client.request("nvim_get_api_info")
        observation["api_version"] = api_metadata["version"]
        client.request(
            "nvim_ui_attach",
            args.width,
            args.height,
            {"rgb": True, "ext_linegrid": True},
        )
        startup_token = "startup"
        startup_timeout = args.timeout if startup else args.prepare_timeout
        client.lua(
            STARTUP_OBSERVER,
            channel,
            startup_token,
            _startup_config(
                project, scenario["file_facts"], item["workload"] == "startup-file"
            ),
            max(1, round(startup_timeout * 1000)),
        )
        initial = client.wait_completion(startup_token, timeout=startup_timeout + 0.5)
        if startup:
            observation["completion"] = initial
        else:
            observation["preparation"].append({"phase": "startup", **initial})
        _require_success(initial, "startup/configuration readiness")
        if startup:
            final = initial
        else:
            if status is not None:
                status(benchmark_progress.preparation_activity(item["workload"]))
            client.lua("dofile(...)", str(HARNESS))
            plan = client.lua(
                "return PoincareBenchmark.prepare(...)",
                item["workload"],
                config,
                channel,
            )
            observation["action"] = plan["action"]
            for index, step in enumerate(plan["steps"]):
                _dispatch_action(client, step, observation["intermediate"])
                prepared = _observe(
                    client, f"prepare-{index}", step["oracle"], args.prepare_timeout
                )
                observation["preparation"].append({"phase": step["oracle"], **prepared})
                _require_success(prepared, f"preparation {step['oracle']}")
            observation["prepared_facts"] = client.lua(
                "return PoincareBenchmark.finalize()"
            )
            client.timeout = args.timeout
            if status is not None:
                status(
                    f"Measuring: {benchmark_progress.workload_label(item['workload'])} "
                    "(display paused)"
                )
            timer_start = time.perf_counter_ns()
            client.operation_deadline = time.monotonic() + args.timeout
            _dispatch_action(client, plan["action"], observation["intermediate"])
            final = _observe(client, "measure", plan["oracle"], args.timeout)
            observation["completion"] = final
            _require_success(final, item["workload"])
        observation["surface_check"] = _surface_check(item["workload"], final["screen"])
        observation["latency_ns"] = final["flush_received_ns"] - timer_start
        if observation["latency_ns"] <= 0:
            raise AcquisitionError("nonpositive measured interval")
        observation["status"] = "ok"
    except AcquisitionTimeout as error:
        observation.update(
            {"status": "timeout", "latency_ns": None, "error": str(error)}
        )
    except Exception as error:
        observation.update(
            {
                "status": "error",
                "latency_ns": None,
                "error": f"{type(error).__name__}: {error}",
                "exception_traceback": traceback.format_exc(),
            }
        )
    finally:
        observation["elapsed_ns"] = time.perf_counter_ns() - elapsed_start
        if timer_start is not None:
            observation["timed_elapsed_ns"] = time.perf_counter_ns() - timer_start
        if client is not None:
            client.startup_prompt_handling = False
            if client.startup_prompt_stopped_ns is None:
                client.startup_prompt_stopped_ns = time.perf_counter_ns()
            observation["last_screen"] = client.screen.snapshot()
            observation["pending_completions"] = client.completions.copy()
            client.operation_deadline = None
            # Runtime facts are outside the scored interval; failures retain the
            # partial UI and stderr even when this best-effort RPC cannot run.
            try:
                client.timeout = min(2.0, args.timeout)
                if observation["status"] != "ok" and not item["workload"].startswith(
                    "startup-"
                ):
                    observation["unscored_last_oracle"] = {
                        "snapshot": client.lua(
                            "return PoincareBenchmark and PoincareBenchmark.last_oracle"
                        ),
                        "captured_at_perf_ns": time.perf_counter_ns(),
                        "boundary": "best-effort last observer state captured after failure; never a scored latency or retry",
                    }
                if item["workload"].startswith("startup-"):
                    client.lua("dofile(...)", str(HARNESS))
                observation["runtime"] = client.lua(
                    "return PoincareBenchmark.runtime()"
                )
            except (AcquisitionError, OSError) as error:
                observation["runtime_error"] = str(error)
            observation["late_completions_outside_boundary"] = client.completions.copy()
            observation.update(client.close())
            runtime = observation.get("runtime", {})
            for tool in runtime.get("tools", {}).values():
                path = tool.get("path")
                if path:
                    if path not in tool_cache:
                        tool_cache[path] = executable_details(Path(path), environment)
                    tool["identity_and_version"] = tool_cache[path]
            runtime["path_sha256"] = hashlib.sha256(
                runtime.get("path", "").encode()
            ).hexdigest()
        observation["finished_at_unix_ns"] = time.time_ns()
    return observation


def _json_safe(value: Any) -> Any:
    if value is None or isinstance(value, (str, bool, int)):
        return value
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError("acquisition evidence contains a nonfinite number")
        return value
    if isinstance(value, bytes):
        return {"hex_bytes": value.hex()}
    if isinstance(value, (list, tuple)):
        return [_json_safe(item) for item in value]
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    raise ValueError(
        f"acquisition evidence is not JSON serializable: {type(value).__name__}"
    )


def _append_journal(stream: Any, record: dict[str, Any]) -> dict[str, Any]:
    safe = _json_safe(record)
    stream.write(
        json.dumps(safe, ensure_ascii=False, allow_nan=False, separators=(",", ":"))
        + "\n"
    )
    stream.flush()
    os.fsync(stream.fileno())
    return safe


def _statistics() -> Any:
    if __package__:
        return importlib.import_module(".benchmark_stats", __package__)
    return importlib.import_module("benchmark_stats")


def _analyze(records: list[dict[str, Any]], args: argparse.Namespace) -> dict[str, Any]:
    manifest = records[0] if records and isinstance(records[0], dict) else {}
    metadata = manifest.get("metadata", {})
    stored = metadata.get("analysis_plan") if isinstance(metadata, dict) else None
    if stored is not None and (
        not isinstance(stored, dict) or set(stored) != set(ANALYSIS_DEFAULTS)
    ):
        raise ValueError(
            "manifest metadata.analysis_plan must contain exactly resamples/confidence/practical/seed/block_length"
        )
    specified = {
        key: getattr(args, key) for key in ANALYSIS_DEFAULTS if hasattr(args, key)
    }
    replay = args.command == "report"
    effective = ANALYSIS_DEFAULTS | {"seed": manifest.get("seed")}
    if stored is not None:
        effective.update(stored)
    effective.update(specified)
    statistics = _statistics()
    analyzed = statistics.analyze(records, **effective)
    analyzed["analysis_overrides"] = {
        "stored_plan": stored,
        "effective_plan": effective,
        "overrides": specified if replay else {},
    }
    analyzed["analysis_source_identity"] = perf.file_identity(Path(statistics.__file__))
    return analyzed


def _print_report(
    report: dict[str, Any],
    as_json: bool,
    *,
    plain: bool = False,
    details: bool = False,
    file: TextIO | None = None,
) -> None:
    stream = sys.stdout if file is None else file
    if as_json:
        print(
            json.dumps(report, ensure_ascii=False, allow_nan=False, indent=2),
            file=stream,
        )
    else:
        display = importlib.import_module(
            ".benchmark_display" if __package__ else "benchmark_display",
            __package__ or None,
        )
        display.print_report(report, plain=plain, details=details, file=stream)


def run(args: argparse.Namespace) -> int:
    with benchmark_progress.BenchmarkProgress(
        enabled=not getattr(args, "no_progress", False),
        plain=getattr(args, "plain", False),
    ) as progress:
        analyzed, successful = _collect_and_analyze(args, progress)
    _print_report(
        analyzed,
        args.json,
        plain=getattr(args, "plain", False),
        details=getattr(args, "details", False),
    )
    return 0 if successful else 1


def _collect_and_analyze(
    args: argparse.Namespace, progress: benchmark_progress.BenchmarkProgress
) -> tuple[dict[str, Any], bool]:
    progress.stage("Loading benchmark dependency")
    # This is the only command that needs MessagePack. Resolve it before any
    # startup timer so first-import cost is not charged to one target/sample.
    try:
        msgpack = importlib.import_module("msgpack")
    except ImportError as error:
        raise AcquisitionError(
            "run requires msgpack; use the packaged Python development shell"
        ) from error
    if not math.isfinite(args.confidence) or not 0 < args.confidence < 1:
        raise ValueError("--confidence must lie strictly between 0 and 1")
    if not math.isfinite(args.practical) or not 0 <= args.practical < 1:
        raise ValueError("--practical must lie in [0, 1)")
    if args.block_length is not None and args.block_length > args.repeat:
        raise ValueError("--block-length cannot exceed --repeat")
    selected = workloads.select_workloads(args.suite, args.workload)
    progress.stage(
        "Resolving editor executables"
        if args.nvim
        else "Resolving and building editor package"
    )
    candidate = (
        perf.resolve_executable(args.nvim)
        if args.nvim
        else pipeline.realise_outputs(ROOT)[0]
    )
    targets = {"candidate": candidate}
    if args.baseline:
        targets = {"baseline": perf.resolve_executable(args.baseline), **targets}
    for name, path in targets.items():
        if not path.is_file() or not os.access(path, os.X_OK):
            raise AcquisitionError(
                f"{name} Neovim executable not found/executable: {path}"
            )
    args.output = args.output.expanduser().absolute()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        raise AcquisitionError(
            f"refusing to overwrite existing evidence journal: {args.output}"
        )
    affinity_before = None
    if args.cpu_affinity is not None:
        if not hasattr(os, "sched_getaffinity") or not hasattr(os, "sched_setaffinity"):
            raise AcquisitionError(
                "explicit CPU affinity is not supported on this platform"
            )
        affinity_before = os.sched_getaffinity(0)
        requested = set(args.cpu_affinity)
        if not requested or not requested <= affinity_before:
            raise AcquisitionError(
                f"--cpu-affinity must select available CPUs: {sorted(affinity_before)}"
            )
        os.sched_setaffinity(0, requested)
    workspace = Path(
        tempfile.mkdtemp(prefix="poincare-benchmark-", dir=args.output.parent)
    )
    records: list[dict[str, Any]] = []
    retain = args.keep_workdir
    complete = False
    try:
        progress.stage("Preparing fixtures and run metadata")
        files = workloads.corpus_files()
        fixture = workloads.corpus_metadata(files)
        facts = workloads.corpus_file_facts(files)
        scenarios = {
            workload.name: workloads.scenario_config(workload, files, facts)
            for workload in selected
        }
        schedule = make_schedule(
            [workload.name for workload in selected],
            list(targets),
            args.repeat,
            args.warmups,
            args.seed,
        )
        progress.configure(
            total=len(schedule), repeat=args.repeat, warmups=args.warmups
        )
        metadata_environment, policy = isolated_environment(
            workspace / "metadata-state"
        )
        manifest = {
            "type": "manifest",
            "format": FORMAT,
            "seed": args.seed,
            "repeat": args.repeat,
            "warmups": args.warmups,
            "targets": list(targets),
            "workloads": [workload.metadata() for workload in selected],
            "schedule": schedule,
            "metadata": {
                "target_identities": {
                    name: executable_details(path, metadata_environment)
                    for name, path in targets.items()
                },
                "host": perf.host_metadata(),
                "python_executable": sys.executable,
                "msgpack_version": getattr(msgpack, "__version__", None),
                "harness": {
                    path.name: perf.file_identity(path)
                    for path in (
                        Path(__file__).resolve(),
                        HARNESS,
                        Path(__file__).with_name("benchmark_workloads.py"),
                        Path(__file__).with_name("benchmark_rpc.py"),
                        Path(benchmark_progress.__file__),
                        Path(_statistics().__file__),
                    )
                },
                "analysis_plan": {key: getattr(args, key) for key in ANALYSIS_DEFAULTS},
                "presentation": {"progress": progress.policy()},
                "flake_lock": perf.file_identity(ROOT / "flake.lock"),
                "fixture": fixture,
                "workspace": str(workspace),
                "state_policy": args.state,
                "environment_policy": policy,
                "ui": {
                    "width": args.width,
                    "height": args.height,
                    "rgb": True,
                    "ext_linegrid": True,
                    "physical_display_latency": False,
                },
                "timing": {
                    "clock": "perf_counter_ns",
                    "poll_cadence_ms": 1,
                    "timeout_s": args.timeout,
                    "prepare_timeout_s": args.prepare_timeout,
                    "interaction": "immediately before input/RPC dispatch to receipt of flush strictly after oracle notification; no overhead subtraction",
                    "startup": "immediately before spawn through attached UI, API handshake, minimal inline readiness observer, startup-only actual return-prompt acknowledgements and first checked redraw; no human think time; full scenario harness excluded",
                    "startup_prompt_policy": "fast nvim_get_mode mode=r gates recorded real <CR>; stop at startup readiness; warnings retained, nonempty vim.v.errmsg is failure",
                    "excluded": [
                        "build",
                        "fixture generation/reset",
                        "interaction preparation",
                        "runtime/identity evidence",
                        "shutdown",
                    ],
                },
                "cache_policy": {
                    "processes": "fresh per observation including warmups",
                    "application": (
                        "HOME/XDG reused per target+workload"
                        if args.state == "warm"
                        else "new HOME/XDG for every observation"
                    ),
                    "fixture": "source content restored before every observation; fixed Git index/commit",
                    "shada": "disabled with -i NONE",
                    "undo": "configured persistent undo retained under isolated state policy",
                    "filesystem": "OS page cache uncontrolled/warmed, never disk-cold",
                },
                "cpu_affinity_requested": args.cpu_affinity,
                "inference_scope": "conditional on this host, synthetic corpus, tool PATH, UI and state policy; no workload weighting or aggregate score",
            },
        }
        tool_cache: dict[str, dict[str, Any]] = {}
        with args.output.open("x", encoding="utf-8") as stream:
            progress.journal_created(args.output)
            records.append(_append_journal(stream, manifest))
            progress.stage("Collecting benchmark observations")
            for index, item in enumerate(schedule):
                key = f"{item['target']}-{item['workload']}"
                state = (
                    workspace
                    / "states"
                    / (key if args.state == "warm" else f"{index:05d}-{key}")
                )
                # Keep fixture path constant across repetitions, including fresh
                # HOME/XDG runs: pin/LSP/project semantics must not drift.
                project = workspace / "projects" / key
                progress.begin(item)
                observation = acquire(
                    item,
                    targets[item["target"]],
                    state,
                    project,
                    files,
                    scenarios[item["workload"]],
                    args,
                    tool_cache,
                    status=progress.status,
                )
                retain = retain or observation["status"] != "ok"
                records.append(_append_journal(stream, observation))
                progress.recorded(records[-1])
            records.append(_append_journal(stream, {"type": "end", "complete": True}))
            complete = True
        progress.stage("Analyzing results and uncertainty")
        report = _analyze(records, args)
        progress.finish(complete=True)
        return report, report["valid"] and all(
            record.get("status", "ok") == "ok" for record in records
        )
    finally:
        progress.finish(complete=False)
        if affinity_before is not None:
            os.sched_setaffinity(0, affinity_before)
        if retain or not complete:
            print(
                f"Benchmark workspace retained: {benchmark_progress.literal(workspace)}",
                file=sys.stderr,
            )
        else:
            shutil.rmtree(workspace)


def report(args: argparse.Namespace) -> int:
    records = _statistics().load_records(args.path)
    analyzed = _analyze(records, args)
    _print_report(
        analyzed,
        args.json,
        plain=getattr(args, "plain", False),
        details=getattr(args, "details", False),
    )
    return 0 if analyzed["valid"] else 1


def _positive_int(value: str) -> int:
    result = int(value)
    if result < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return result


def _nonnegative_int(value: str) -> int:
    result = int(value)
    if result < 0:
        raise argparse.ArgumentTypeError("must be a nonnegative integer")
    return result


def _positive_float(value: str) -> float:
    result = float(value)
    if not math.isfinite(result) or result <= 0:
        raise argparse.ArgumentTypeError("must be positive and finite")
    return result


def _affinity(value: str) -> list[int]:
    try:
        result = [int(item) for item in value.split(",")]
    except ValueError as error:
        raise argparse.ArgumentTypeError("use comma-separated CPU numbers") from error
    if any(item < 0 for item in result) or len(set(result)) != len(result):
        raise argparse.ArgumentTypeError("CPU numbers must be unique and nonnegative")
    return result


def _selection(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--suite",
        action="append",
        choices=workloads.SUITES,
        help="repeatable suite union; run defaults to core, list to all",
    )
    parser.add_argument(
        "--workload",
        action="append",
        choices=tuple(workloads.BY_NAME),
        help="repeatable explicit workload; alone selects only these names",
    )


def _analysis_options(parser: argparse.ArgumentParser, *, replay: bool = False) -> None:
    defaults = (
        {key: argparse.SUPPRESS for key in ANALYSIS_DEFAULTS}
        if replay
        else ANALYSIS_DEFAULTS
    )
    parser.add_argument(
        "--resamples", type=_positive_int, default=defaults["resamples"]
    )
    parser.add_argument("--confidence", type=float, default=defaults["confidence"])
    parser.add_argument("--practical", type=float, default=defaults["practical"])
    parser.add_argument(
        "--seed",
        type=_nonnegative_int,
        default=defaults["seed"],
        help="schedule/bootstrap seed; report defaults to stored analysis plan; does not control host noise",
    )
    parser.add_argument(
        "--block-length", type=_positive_int, default=defaults["block_length"]
    )
    parser.add_argument(
        "--json", action="store_true", help="print the analyzed report as JSON"
    )
    parser.add_argument(
        "--details",
        action="store_true",
        help="show the full statistical report instead of the concise results",
    )
    parser.add_argument(
        "--plain", action="store_true", help="use ANSI-free plain reports and progress"
    )


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    listing = commands.add_parser(
        "list", help="show exact requirements, state and latency boundaries"
    )
    _selection(listing)
    listing.add_argument("--json", action="store_true")
    running = commands.add_parser(
        "run",
        help="collect fresh-process observations into an incremental JSONL journal",
    )
    _selection(running)
    _analysis_options(running)
    running.add_argument(
        "--no-progress", action="store_true", help="silence progress on stderr"
    )
    running.add_argument("--output", required=True, type=Path)
    running.add_argument(
        "--nvim",
        type=Path,
        help="candidate packaged executable; default: pipeline.realise_outputs",
    )
    running.add_argument(
        "--baseline",
        type=Path,
        help="optional baseline executable; pairs are adjacent and balanced AB/BA",
    )
    running.add_argument("--repeat", type=_positive_int, default=30)
    running.add_argument("--warmups", type=_nonnegative_int, default=3)
    running.add_argument("--state", choices=("warm", "fresh"), default="warm")
    running.add_argument("--width", type=_positive_int, default=120)
    running.add_argument("--height", type=_positive_int, default=40)
    running.add_argument(
        "--timeout",
        type=_positive_float,
        default=30.0,
        help="bounded measured operation/startup seconds",
    )
    running.add_argument(
        "--prepare-timeout",
        type=_positive_float,
        default=60.0,
        help="bounded untimed startup/preparation oracle seconds",
    )
    running.add_argument(
        "--cpu-affinity",
        type=_affinity,
        help="optional explicit available CPU list; no automatic scheduling changes",
    )
    running.add_argument(
        "--keep-workdir",
        action="store_true",
        help="retain isolated state/fixtures even on success; failures always retain them",
    )
    reporting = commands.add_parser(
        "report", help="replay and validate a journal without Nix, Neovim, or msgpack"
    )
    reporting.add_argument("path", type=Path)
    _analysis_options(reporting, replay=True)
    return result


def main(argv: list[str] | None = None) -> int:
    arguments = parser().parse_args(argv)
    try:
        if arguments.command == "list":
            suites = arguments.suite or ([] if arguments.workload else ["all"])
            selected = workloads.select_workloads(suites, arguments.workload)
            if arguments.json:
                print(
                    json.dumps(
                        {
                            "workloads": [item.metadata() for item in selected],
                            "fixture": workloads.corpus_metadata(
                                workloads.corpus_files()
                            ),
                            "default_run_suite": "core",
                            "state_policy": "warm HOME/XDG by default; every process fresh; never disk-cold",
                        },
                        indent=2,
                    )
                )
            else:
                for item in selected:
                    print(
                        f"{item.name} [{item.suite}]\n  {item.description}"
                        f"\n  Requires: {'; '.join(item.requirements)}"
                        f"\n  Fixtures: {'; '.join(item.fixtures) or 'empty editor in generated Git project'}"
                        f"\n  Action: {item.action}\n  Readiness: {item.readiness}"
                        f"\n  State: {item.application_state}\n  Latency: {item.latency_boundary}"
                        f"\n  Limitations: {'; '.join(item.limitations)}"
                    )
                fixture = workloads.corpus_metadata(workloads.corpus_files())
                print(
                    f"\nCorpus {fixture['schema']}: {fixture['file_count']} files, {fixture['bytes']} bytes, {fixture['lines']} lines; sha256 {fixture['sha256']}"
                )
                print(
                    "Every case uses a fresh process and attached UI. Default run suite: core. Application state: warm isolated HOME/XDG (or --state fresh); OS pages are never claimed disk-cold. All cases require git for deterministic corpus setup. Poll cadence: 1ms; no calibration subtraction."
                )
            return 0
        if arguments.command == "run":
            if arguments.width < 60 or arguments.height < 20:
                raise ValueError(
                    "the checked viewport/split corpus requires --width >= 60 and --height >= 20"
                )
            return run(arguments)
        return report(arguments)
    except KeyboardInterrupt:
        print(
            "benchmark interrupted; retained journal is incomplete and cannot support inference",
            file=sys.stderr,
        )
        return 130
    except (AcquisitionError, pipeline.AnalysisError, OSError, ValueError) as error:
        print(f"benchmark: {benchmark_progress.literal(error)}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
