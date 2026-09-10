#!/usr/bin/env python3
"""Acquire complete Neovim performance observations; policy lives in pipeline."""

from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

try:
    from scripts import pipeline
except ModuleNotFoundError:
    import pipeline  # type: ignore[no-redef]

ROOT = Path(__file__).resolve().parent.parent
HARNESS = Path(__file__).resolve().with_name("profile.lua")
RAW_FORMAT = "poincare-perf-raw/v1"


def file_identity(path: Path) -> dict[str, Any]:
    try:
        resolved = path.resolve(strict=True)
        content = resolved.read_bytes()
    except OSError as error:
        return {"identity": None, "error": str(error)}
    return {
        "identity": {
            "path": str(path),
            "resolved_path": str(resolved),
            "byte_length": len(content),
            "sha256": hashlib.sha256(content).hexdigest(),
        },
        "error": None,
    }


def resolve_executable(path: Path) -> Path:
    if path.parent != Path("."):
        return path.expanduser().resolve()
    found = shutil.which(str(path))
    return Path(found).resolve() if found else path.resolve()


def host_metadata() -> dict[str, Any]:
    affinity = None
    if hasattr(os, "sched_getaffinity"):
        try:
            affinity = sorted(os.sched_getaffinity(0))
        except OSError:
            pass
    cpu_model = platform.processor() or None
    try:
        for line in Path("/proc/cpuinfo").read_text(errors="replace").splitlines():
            if line.lower().startswith(("model name", "hardware")):
                cpu_model = line.partition(":")[2].strip() or cpu_model
                break
    except OSError:
        pass
    clock = time.get_clock_info("perf_counter")
    return {
        "os": platform.system(),
        "kernel": platform.release(),
        "architecture": platform.machine(),
        "cpu_model": cpu_model,
        "cpu_count": os.cpu_count(),
        "cpu_affinity": affinity,
        "clock": {
            "implementation": clock.implementation,
            "resolution_ns": round(clock.resolution * 1_000_000_000),
            "monotonic": clock.monotonic,
            "adjustable": clock.adjustable,
        },
        "python": platform.python_version(),
    }


def _environment(home: Path) -> tuple[dict[str, str], dict[str, Any]]:
    environment = os.environ.copy()
    directories = {}
    for kind in ("config", "data", "state", "cache"):
        path = home / kind
        path.mkdir()
        key = f"XDG_{kind.upper()}_HOME"
        environment[key] = str(path)
        directories[key] = "isolated-per-attempt"
    for kind in ("config-dirs", "data-dirs"):
        (home / kind).mkdir()
    environment["XDG_CONFIG_DIRS"] = str(home / "config-dirs")
    environment["XDG_DATA_DIRS"] = str(home / "data-dirs")
    unset = [
        "TMUX", "TMUX_PANE", "NVIM", "NVIM_LISTEN_ADDRESS", "NVIM_APPNAME",
        "VIMRUNTIME", "VIMINIT", "EXINIT", "LUA_INIT", "LUA_PATH", "LUA_CPATH",
    ]
    for key in unset:
        environment.pop(key, None)
    environment["NVIM_LOG_FILE"] = os.devnull
    return environment, {
        "xdg": directories,
        "xdg_system_dirs": "isolated-per-attempt",
        "unset": unset,
        "NVIM_LOG_FILE": os.devnull,
        "inherited_values": {
            key: environment.get(key) for key in ("LANG", "LC_ALL", "TERM")
        },
        "path_sha256": hashlib.sha256(environment.get("PATH", "").encode()).hexdigest(),
        "home": "inherited",
    }


def run_attempt(
    nvim: Path,
    workload: dict[str, Any],
    mode: str,
    iteration: int,
    warmup: bool,
    timeout: float,
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix=f"poincare-perf-{workload['name']}-{mode}-") as temporary:
        session = Path(temporary)
        config_path = session / "workload.json"
        output_path = session / "trace.json"
        startup_path = session / "startuptime.log"
        config_path.write_text(json.dumps(workload["config"], separators=(",", ":")))
        environment, policy = _environment(session)
        environment.update({
            "POINCARE_PERF_CONFIG": str(config_path),
            "POINCARE_PERF_OUTPUT": str(output_path),
        })
        argv = [str(nvim), "--headless", "-i", "NONE", "-n"]
        if mode == "profile":
            argv.extend([
                "--startuptime", str(startup_path),
                "--cmd", f"lua dofile({json.dumps(str(HARNESS))}).preinit()",
            ])
        argv.extend(workload["config"].get("args", []))
        argv.extend(["-c", f"lua dofile({json.dumps(str(HARNESS))}).run()"])
        started_at = time.time_ns()
        started = time.perf_counter_ns()
        returncode: int | None = None
        stdout = ""
        stderr = ""
        launch_error = None
        timed_out = False
        process: subprocess.Popen[str] | None = None
        try:
            process = subprocess.Popen(
                argv,
                cwd=session,
                env=environment,
                text=True,
                encoding="utf-8",
                errors="replace",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
            )
            try:
                stdout, stderr = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                stdout, stderr = process.communicate()
            returncode = process.returncode
        except KeyboardInterrupt:
            if process is not None and process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.communicate()
            raise
        except OSError as error:
            launch_error = str(error)
        wall_ns = time.perf_counter_ns() - started
        trace = None
        trace_error = None
        try:
            trace = output_path.read_text()
        except OSError as error:
            trace_error = str(error)
        try:
            startuptime = startup_path.read_text() if mode == "profile" else None
        except OSError as error:
            startuptime = None
            trace_error = f"{trace_error}; startuptime: {error}" if trace_error else f"startuptime: {error}"
        return {
            "workload": workload["name"],
            "workload_sha256": workload["sha256"],
            "mode": mode,
            "iteration": iteration,
            "warmup": warmup,
            "started_at_unix_ns": started_at,
            "wall_ns": wall_ns,
            "argv": argv,
            "cwd": str(session),
            "environment_policy": policy,
            "returncode": returncode,
            "stdout": stdout,
            "stderr": stderr,
            "timed_out": timed_out,
            "launch_error": launch_error,
            "trace": trace,
            "trace_read_error": trace_error,
            "startuptime": startuptime,
        }


def collect(
    nvim: Path,
    workloads: list[dict[str, Any]],
    *,
    repeat: int,
    warmups: int,
    timeout: float,
) -> dict[str, Any]:
    nvim = resolve_executable(nvim)
    executable_identity = file_identity(nvim)
    harness_identity = file_identity(HARNESS)
    observations = []
    schedule = []
    for workload in workloads:
        for mode in ("wall", "profile"):
            for index in range(warmups + repeat):
                warmup = index < warmups
                schedule.append({"workload": workload["name"], "mode": mode, "iteration": index, "warmup": warmup})
                observations.append(run_attempt(nvim, workload, mode, index, warmup, timeout))
    return {
        "format": RAW_FORMAT,
        "workloads": workloads,
        "collection": {
            "repeat": repeat,
            "warmups": warmups,
            "timeout_seconds": timeout,
            "schedule": schedule,
            "cache_policy": "fresh process and isolated XDG directories; warm filesystem cache",
            "wall_clock_scope": "Python perf_counter_ns around process launch through shutdown",
        },
        "collector": {
            "executable": executable_identity,
            "harness": harness_identity,
            "host": host_metadata(),
        },
        "observations": observations,
    }


def main(argv: list[str] | None = None) -> int:
    return pipeline.main(["perf", *(sys.argv[1:] if argv is None else argv)])


if __name__ == "__main__":
    raise SystemExit(main())
