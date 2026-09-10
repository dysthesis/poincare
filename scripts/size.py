#!/usr/bin/env python3
"""Collect poincare LuaJIT bytecode without interpreting probe output."""

from __future__ import annotations

import json
import hashlib
import os
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from scripts import pipeline
except ModuleNotFoundError:  # Direct execution from an archived scripts directory.
    import pipeline  # type: ignore[no-redef]

ROOT = Path(__file__).resolve().parent.parent
ADAPTER = Path(__file__).resolve().with_name("bytecode.lua")
RAW_FORMAT = "poincare-size-raw/v1"
AnalysisError = pipeline.AnalysisError


@dataclass(frozen=True)
class Source:
    id: int
    logical: tuple[str, ...]
    path: Path


def _lua_files(
    root: Path, logical: tuple[str, ...]
) -> list[tuple[tuple[str, ...], Path]]:
    found: list[tuple[tuple[str, ...], Path]] = []
    try:
        owner = root.resolve(strict=True)
    except OSError as error:
        raise AnalysisError(f"cannot resolve source root {root}: {error}") from error

    def visit(
        path: Path, parts: tuple[str, ...], ancestors: frozenset[tuple[int, int]]
    ) -> None:
        is_directory = path.is_dir()
        if not is_directory and not path.name.endswith(".lua"):
            return
        try:
            resolved = path.resolve(strict=True)
            stat = path.stat()
        except OSError as error:
            raise AnalysisError(f"cannot follow {path}: {error}") from error
        if not is_directory and not resolved.is_relative_to(owner):
            raise AnalysisError(
                f"source symlink escapes owner root {root}: {path} -> {resolved}"
            )
        key = (stat.st_dev, stat.st_ino)
        if is_directory:
            if key in ancestors:
                raise AnalysisError(f"directory traversal cycle at {path}")
            try:
                entries = sorted(path.iterdir(), key=lambda entry: entry.name)
            except OSError as error:
                raise AnalysisError(f"cannot read directory {path}: {error}") from error
            for entry in entries:
                visit(entry, parts + (entry.name,), ancestors | {key})
        elif path.name.endswith(".lua"):
            found.append((logical + parts, path))

    visit(root, (), frozenset())
    return found


def discover(packpath: Path) -> list[Source]:
    if not packpath.is_dir():
        raise AnalysisError(f"packpath is not a directory: {packpath}")
    candidates: list[tuple[tuple[str, ...], Path]] = []
    for entry in sorted(packpath.iterdir(), key=lambda path: path.name):
        if entry.name != "pack":
            candidates.extend(_lua_files(entry, ("config", entry.name)))

    pack = packpath / "pack"
    if not pack.is_dir():
        raise AnalysisError(f"packpath has no pack directory: {pack}")
    for namespace in sorted(pack.iterdir(), key=lambda path: path.name):
        if namespace.is_symlink() and not namespace.exists():
            raise AnalysisError(f"broken namespace link: {namespace}")
        if not namespace.is_dir():
            continue
        for kind in ("start", "opt"):
            plugin_root = namespace / kind
            if plugin_root.is_symlink() and not plugin_root.exists():
                raise AnalysisError(f"broken plugin root link: {plugin_root}")
            if not plugin_root.exists():
                continue
            if not plugin_root.is_dir():
                raise AnalysisError(f"plugin root is not a directory: {plugin_root}")
            for plugin in sorted(plugin_root.iterdir(), key=lambda path: path.name):
                if plugin.is_symlink() and not plugin.exists():
                    raise AnalysisError(f"broken plugin link: {plugin}")
                if not plugin.is_dir():
                    raise AnalysisError(f"plugin entry is not a directory: {plugin}")
                candidates.extend(_lua_files(plugin, ("plugins", plugin.name)))

    candidates.sort(key=lambda item: (item[0], os.fspath(item[1])))
    collisions: dict[tuple[str, ...], Path] = {}
    sources: list[Source] = []
    for logical, path in candidates:
        previous = collisions.get(logical)
        if previous is not None:
            raise AnalysisError(
                f"logical source collision at {'/'.join(logical)}: {previous} and {path}"
            )
        collisions[logical] = path
        sources.append(Source(len(sources), logical, path))
    return sources


def _file_identity(path: Path) -> dict[str, Any]:
    try:
        resolved = path.resolve(strict=True)
        content = resolved.read_bytes()
    except OSError as error:
        raise AnalysisError(f"cannot identify {path}: {error}") from error
    return {
        "path": str(path),
        "resolved_path": str(resolved),
        "byte_length": len(content),
        "sha256": hashlib.sha256(content).hexdigest(),
    }


def probe(nvim: Path, sources: list[Source]) -> dict[str, Any]:
    manifest = {
        "sources": [{"id": source.id, "path": str(source.path)} for source in sources]
    }
    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8") as handle:
        json.dump(manifest, handle, separators=(",", ":"))
        handle.flush()
        environment = os.environ.copy()
        environment["NVIM_LOG_FILE"] = "/dev/null"
        command = [
            str(nvim), "-u", "NONE", "-i", "NONE", "--noplugin", "-n",
            "-l", str(ADAPTER), handle.name,
        ]
        started = time.perf_counter_ns()
        try:
            result = subprocess.run(
                command,
                text=True,
                capture_output=True,
                env=environment,
            )
        except OSError as error:
            return {
                "argv": command,
                "duration_ns": time.perf_counter_ns() - started,
                "returncode": None,
                "stdout": "",
                "stderr": "",
                "launch_error": str(error),
            }
    return {
        "argv": command,
        "duration_ns": time.perf_counter_ns() - started,
        "returncode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "launch_error": None,
    }


def collect(nvim: Path, packpath: Path) -> dict[str, Any]:
    sources = discover(packpath)
    if not sources:
        raise AnalysisError(f"no Lua sources found under {packpath}")
    try:
        resolved_packpath = packpath.resolve(strict=True)
    except OSError as error:
        raise AnalysisError(f"cannot identify {packpath}: {error}") from error
    return {
        "format": RAW_FORMAT,
        "collector": {
            "nvim": _file_identity(nvim),
            "adapter": _file_identity(ADAPTER),
            "packpath": {
                "path": str(packpath),
                "resolved_path": str(resolved_packpath),
            },
        },
        "manifest": [
            {
                "id": source.id,
                "logical": list(source.logical),
                **_file_identity(source.path),
            }
            for source in sources
        ],
        "probe": probe(nvim, sources),
    }


def main(argv: list[str] | None = None) -> int:
    return pipeline.main(["size", *(sys.argv[1:] if argv is None else argv)])


if __name__ == "__main__":
    raise SystemExit(main())
