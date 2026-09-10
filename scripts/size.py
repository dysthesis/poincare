#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from collections import Counter
from collections.abc import Iterable
from dataclasses import dataclass, field, fields
from pathlib import Path
from statistics import quantiles
from typing import IO, Any

ROOT = Path(__file__).resolve().parent.parent
ADAPTER = Path(__file__).resolve().with_name("bytecode.lua")
OUTPUT_FORMAT = "poincare-size/v1"
NOTES_REF = "refs/notes/poincare-size"
# Minimum terminal width in columns before bars/sparklines are drawn.
GRAPH_MIN_WIDTH = 100
METRIC_NAMES = {
    "bytecodes": "bytecodes",
    "decisions": "decisions",
    "functions": "functions",
    "calls": "calls",
    "closures": "closures",
    "tables": "tables",
    "global-reads": "global_reads",
    "global-writes": "global_writes",
    "upvalue-reads": "upvalue_reads",
    "upvalue-writes": "upvalue_writes",
}
KNOWN_OPS = frozenset(
    """ISLT ISGE ISLE ISGT ISEQV ISNEV ISEQS ISNES ISEQN ISNEN ISEQP ISNEP
    ISTC ISFC IST ISF ISTYPE ISNUM MOV NOT UNM LEN ADDVN SUBVN MULVN DIVVN MODVN
    ADDNV SUBNV MULNV DIVNV MODNV ADDVV SUBVV MULVV DIVVV MODVV POW CAT KSTR
    BNOT BAND BOR BXOR BSHL BSHR BSAR KCDATA KSHORT KNUM KPRI KNIL UGET USETV
    USETS USETN USETP UCLO FNEW TNEW TDUP GGET GSET TGETV TGETS TGETB TGETR
    TSETV TSETS TSETB TSETM TSETR
    CALLM CALL CALLMT CALLT ITERC ITERN VARG ISNEXT RETM RET RET0 RET1 FORI
    JFORI FORL IFORL JFORL ITERL IITERL JITERL LOOP ILOOP JLOOP JMP FUNCF
    IFUNCF JFUNCF FUNCV IFUNCV JFUNCV FUNCC FUNCCW""".split()
)
TEST_OPS = {
    "ISLT",
    "ISGE",
    "ISLE",
    "ISGT",
    "ISEQV",
    "ISNEV",
    "ISEQS",
    "ISNES",
    "ISEQN",
    "ISNEN",
    "ISEQP",
    "ISNEP",
    "ISTC",
    "ISFC",
    "IST",
    "ISF",
}
TARGET_ONLY = {"JMP", "UCLO", "ISNEXT"}
TARGET_AND_NEXT = {"FORI", "JFORI", "FORL", "IFORL", "ITERL", "IITERL"}
TARGET_OPS = TARGET_ONLY | TARGET_AND_NEXT | {"LOOP", "ILOOP"}
ITER_CALLS = {"ITERC", "ITERN"}
ITER_LOOPS = {"ITERL", "IITERL"}
TERMINALS = {"RETM", "RET", "RET0", "RET1", "CALLT", "CALLMT"}
UNSUPPORTED = {"JFORL", "JITERL", "JLOOP", "JFUNCF", "JFUNCV"}
ORDINARY_OPS = KNOWN_OPS - (
    TEST_OPS
    | TARGET_ONLY
    | TARGET_AND_NEXT
    | {"LOOP", "ILOOP"}
    | TERMINALS
    | UNSUPPORTED
)


class AnalysisError(RuntimeError):
    pass


@dataclass(frozen=True)
class Source:
    id: int
    logical: tuple[str, ...]
    path: Path


@dataclass(frozen=True)
class Instruction:
    pc: int
    opcode: str
    target: int | None = None


@dataclass(frozen=True)
class Unit:
    start: int
    end: int
    successors: tuple[int, ...]


@dataclass(frozen=True)
class Block:
    start: int
    end: int
    successors: tuple[int, ...]


@dataclass
class Metrics:
    bytecodes: int = 0
    functions: int = 0
    decisions: int = 0
    calls: int = 0
    closures: int = 0
    tables: int = 0
    global_reads: int = 0
    global_writes: int = 0
    upvalue_reads: int = 0
    upvalue_writes: int = 0

    def __add__(self, other: Metrics) -> Metrics:
        return Metrics(
            **{
                item.name: getattr(self, item.name) + getattr(other, item.name)
                for item in fields(self)
            }
        )

    def empty(self) -> bool:
        return not any(getattr(self, item.name) for item in fields(self))


@dataclass
class Node:
    name: str
    own: Metrics = field(default_factory=Metrics)
    total: Metrics = field(default_factory=Metrics)
    children: dict[str, Node] = field(default_factory=dict)


@dataclass
class History:
    samples: list[dict[tuple[str, ...], Metrics]] = field(default_factory=list)
    ancestors: int = 0
    skipped: Counter[str] = field(default_factory=Counter)
    warnings: list[str] = field(default_factory=list)


def realise_outputs() -> tuple[Path, Path]:
    command = [
        "nix",
        "build",
        "--no-link",
        "--print-out-paths",
        ".#poincare",
        ".#poincare.packpath",
    ]
    try:
        result = subprocess.run(
            command, cwd=ROOT, text=True, capture_output=True, check=False
        )
    except FileNotFoundError as error:
        raise AnalysisError("nix is required to realise poincare") from error
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise AnalysisError(f"nix build failed: {detail}")
    outputs = [Path(line) for line in result.stdout.splitlines() if line.strip()]
    nvim_outputs = [path for path in outputs if (path / "bin" / "nvim").is_file()]
    pack_outputs = [path for path in outputs if (path / "pack").is_dir()]
    if len(outputs) != 2 or len(nvim_outputs) != 1 or len(pack_outputs) != 1:
        raise AnalysisError(
            "could not classify the two Nix outputs by bin/nvim and pack/"
        )
    return nvim_outputs[0] / "bin" / "nvim", pack_outputs[0]


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
        if is_directory and path != root and path.name == "tests":
            return
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
            joined = "/".join(logical)
            raise AnalysisError(
                f"logical source collision at {joined}: {previous} and {path}"
            )
        collisions[logical] = path
        sources.append(Source(len(sources), logical, path))
    return sources


def probe(nvim: Path, sources: list[Source]) -> dict[str, Any]:
    manifest = {
        "sources": [{"id": source.id, "path": str(source.path)} for source in sources]
    }
    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8") as handle:
        json.dump(manifest, handle, separators=(",", ":"))
        handle.flush()
        command = [
            str(nvim),
            "-u",
            "NONE",
            "-i",
            "NONE",
            "--noplugin",
            "-n",
            "-l",
            str(ADAPTER),
            handle.name,
        ]
        environment = os.environ.copy()
        environment["NVIM_LOG_FILE"] = "/dev/null"
        try:
            result = subprocess.run(
                command, text=True, capture_output=True, env=environment
            )
        except OSError as error:
            raise AnalysisError(
                f"cannot run realised Neovim {nvim}: {error}"
            ) from error
    if result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise AnalysisError(f"Neovim bytecode probe failed: {detail}")
    try:
        decoder = json.JSONDecoder()
        response, end = decoder.raw_decode(result.stdout)
        if result.stdout[end:].strip():
            raise ValueError("trailing output")
    except (json.JSONDecodeError, ValueError) as error:
        stderr = result.stderr.strip()
        detail = f"; stderr: {stderr}" if stderr else ""
        raise AnalysisError(
            f"bytecode probe did not return one JSON document{detail}"
        ) from error
    return validate_response(response, sources)


def _exact_object(value: Any, keys: set[str], context: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise AnalysisError(f"invalid {context} object")
    return value


def _integer(value: Any, context: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise AnalysisError(f"invalid {context}")
    return value


def validate_response(response: Any, sources: list[Source]) -> dict[str, Any]:
    response = _exact_object(response, {"runtime", "vm", "sources"}, "response")
    runtime = _exact_object(response["runtime"], {"version", "arch", "os"}, "runtime")
    if not all(isinstance(runtime[key], str) for key in runtime):
        raise AnalysisError("invalid runtime values")
    vm = _exact_object(
        response["vm"],
        {"opcode_width", "opcode_bits", "jump_mode", "jump_bias", "opcodes"},
        "VM metadata",
    )
    if (
        vm["opcode_width"] != 6
        or vm["opcode_bits"] != 8
        or vm["jump_mode"] != 13
        or vm["jump_bias"] != 0x7FFF
    ):
        raise AnalysisError("unsupported LuaJIT bytecode ABI")
    opcodes = vm["opcodes"]
    if not isinstance(opcodes, list) or not all(
        isinstance(opcode, str) for opcode in opcodes
    ):
        raise AnalysisError("invalid LuaJIT opcode metadata")
    runtime_ops = set(opcodes)
    if len(opcodes) != len(runtime_ops):
        raise AnalysisError("duplicate LuaJIT opcode metadata")
    if added := sorted(runtime_ops - KNOWN_OPS):
        raise AnalysisError(f"unsupported LuaJIT opcode universe (added={added})")
    items = response["sources"]
    if not isinstance(items, list):
        raise AnalysisError("invalid sources array")
    expected = {source.id for source in sources}
    seen: set[int] = set()
    errors: list[str] = []
    by_id: dict[int, dict[str, Any]] = {}
    for item in items:
        if not isinstance(item, dict) or set(item) not in (
            {"id", "prototypes"},
            {"id", "error"},
        ):
            raise AnalysisError("invalid source result object")
        source_id = _integer(item["id"], "source id")
        if source_id not in expected or source_id in seen:
            raise AnalysisError(f"unexpected or duplicate source id {source_id}")
        seen.add(source_id)
        if "error" in item:
            if not isinstance(item["error"], str):
                raise AnalysisError(f"invalid error for source {source_id}")
            errors.append(f"{sources[source_id].path}: {item['error']}")
            continue
        prototypes = item["prototypes"]
        if not isinstance(prototypes, list) or not prototypes:
            raise AnalysisError(f"invalid prototypes for source {source_id}")
        for prototype in prototypes:
            prototype = _exact_object(prototype, {"info", "instructions"}, "prototype")
            info = _exact_object(
                prototype["info"],
                {
                    "bytecodes",
                    "gcconsts",
                    "nconsts",
                    "params",
                    "stackslots",
                    "upvalues",
                    "isvararg",
                },
                "prototype info",
            )
            for key in (
                "bytecodes",
                "gcconsts",
                "nconsts",
                "params",
                "stackslots",
                "upvalues",
            ):
                _integer(info[key], f"prototype {key}")
            if not isinstance(info["isvararg"], bool):
                raise AnalysisError("invalid prototype isvararg")
            instructions = prototype["instructions"]
            if not isinstance(instructions, list):
                raise AnalysisError("invalid instructions array")
            if info["bytecodes"] != len(instructions) + 1:
                raise AnalysisError(
                    "prototype bytecode count does not include exactly one header"
                )
            for pc, instruction in enumerate(instructions, 1):
                if not isinstance(instruction, dict) or set(instruction) not in (
                    {"pc", "opcode"},
                    {"pc", "opcode", "target"},
                ):
                    raise AnalysisError("invalid instruction object")
                if _integer(instruction["pc"], "instruction pc", 1) != pc:
                    raise AnalysisError("instruction PCs are not contiguous")
                opcode = instruction["opcode"]
                if not isinstance(opcode, str) or opcode not in KNOWN_OPS:
                    raise AnalysisError("invalid instruction opcode")
                has_target = "target" in instruction
                if has_target != (opcode in TARGET_OPS):
                    requirement = (
                        "requires" if opcode in TARGET_OPS else "must not have"
                    )
                    raise AnalysisError(
                        f"instruction {opcode} at PC {pc} {requirement} a target"
                    )
                if has_target:
                    target = _integer(instruction["target"], "instruction target", 1)
                    if target > len(instructions):
                        raise AnalysisError(
                            f"instruction {opcode} at PC {pc} targets invalid PC {target}"
                        )
            prototype["instructions"] = [
                Instruction(item["pc"], item["opcode"], item.get("target"))
                for item in instructions
            ]
        by_id[source_id] = item
    missing = expected - seen
    if missing:
        raise AnalysisError(f"bytecode response omitted source IDs: {sorted(missing)}")
    if errors:
        raise AnalysisError("Lua compilation failed:\n" + "\n".join(errors))
    response["sources"] = by_id
    return response


def build_cfg(instructions: list[Instruction]) -> list[Block]:
    if not instructions:
        return []
    count = len(instructions)
    units: list[Unit] = []
    interiors: set[int] = set()
    pc = 1

    def target(instruction: Instruction) -> int:
        if instruction.target is None:
            raise AnalysisError(
                f"{instruction.opcode} at PC {instruction.pc} has no target"
            )
        if instruction.target < 1 or instruction.target > count:
            raise AnalysisError(
                f"{instruction.opcode} at PC {instruction.pc} targets invalid PC {instruction.target}"
            )
        return instruction.target

    while pc <= count:
        instruction = instructions[pc - 1]
        opcode = instruction.opcode
        if opcode in UNSUPPORTED or opcode.startswith("JFUNC"):
            raise AnalysisError(f"unsupported JIT-patched opcode {opcode} at PC {pc}")
        if opcode in TEST_OPS:
            if pc == count or instructions[pc].opcode != "JMP":
                raise AnalysisError(
                    f"test opcode {opcode} at PC {pc} is not followed by JMP"
                )
            jump = instructions[pc]
            interiors.add(pc + 1)
            units.append(Unit(pc, pc + 1, (target(jump), pc + 2)))
            pc += 2
            continue
        if (
            opcode in ITER_CALLS
            and pc < count
            and instructions[pc].opcode in ITER_LOOPS
        ):
            loop = instructions[pc]
            interiors.add(pc + 1)
            units.append(Unit(pc, pc + 1, (target(loop), pc + 2)))
            pc += 2
            continue
        if opcode in TARGET_ONLY:
            successors = (target(instruction),)
        elif opcode in TARGET_AND_NEXT:
            successors = (target(instruction), pc + 1)
        elif opcode in {"LOOP", "ILOOP"}:
            successors = (pc + 1,)
        elif opcode in TERMINALS:
            successors = ()
        elif opcode in ORDINARY_OPS:
            successors = (pc + 1,) if pc < count else ()
        else:
            raise AnalysisError(f"unmodelled control-flow opcode {opcode} at PC {pc}")
        units.append(Unit(pc, pc, successors))
        pc += 1

    starts = {unit.start for unit in units}
    for unit in units:
        for successor in unit.successors:
            if successor <= count and successor in interiors:
                raise AnalysisError(
                    f"control flow targets grouped instruction at PC {successor}"
                )
            if successor <= count and successor not in starts:
                raise AnalysisError(
                    f"control flow targets invalid semantic unit at PC {successor}"
                )

    leaders = {1}
    for index, unit in enumerate(units):
        opcode = instructions[unit.start - 1].opcode
        straight_line = (
            opcode in ORDINARY_OPS and unit.start == unit.end
        ) or opcode in {"LOOP", "ILOOP"}
        if not straight_line:
            leaders.update(
                successor for successor in unit.successors if successor <= count
            )
            if index + 1 < len(units):
                leaders.add(units[index + 1].start)
    blocks: list[Block] = []
    current: list[Unit] = []
    for unit in units:
        if current and unit.start in leaders:
            last = current[-1]
            blocks.append(Block(current[0].start, last.end, last.successors))
            current = []
        current.append(unit)
    if current:
        last = current[-1]
        blocks.append(Block(current[0].start, last.end, last.successors))
    return blocks


def prototype_metrics(instructions: list[Instruction]) -> Metrics:
    blocks = build_cfg(instructions)
    opcodes = [instruction.opcode for instruction in instructions]
    return Metrics(
        bytecodes=len(instructions),
        functions=1,
        decisions=sum(max(0, len(block.successors) - 1) for block in blocks),
        calls=sum(
            opcode in {"CALL", "CALLM", "CALLT", "CALLMT", "ITERC", "ITERN"}
            for opcode in opcodes
        ),
        closures=opcodes.count("FNEW"),
        tables=sum(opcode in {"TNEW", "TDUP"} for opcode in opcodes),
        global_reads=opcodes.count("GGET"),
        global_writes=opcodes.count("GSET"),
        upvalue_reads=opcodes.count("UGET"),
        upvalue_writes=sum(
            opcode in {"USETV", "USETS", "USETN", "USETP"} for opcode in opcodes
        ),
    )


def aggregate(sources: list[Source], response: dict[str, Any]) -> Node:
    root = Node("poincare")
    for source in sources:
        metrics = Metrics()
        for prototype in response["sources"][source.id]["prototypes"]:
            metrics = metrics + prototype_metrics(prototype["instructions"])
        node = root
        for part in source.logical:
            node = node.children.setdefault(part, Node(part))
        node.own = node.own + metrics

    def total(node: Node) -> Metrics:
        node.total = node.own
        for child in node.children.values():
            node.total = node.total + total(child)
        return node.total

    total(root)
    return root


def assert_aggregation(node: Node) -> Metrics:
    expected = node.own
    for child in node.children.values():
        expected = expected + assert_aggregation(child)
    if expected != node.total:
        raise AnalysisError(f"aggregation invariant failed at {node.name}")
    return expected


def _metrics_object(metrics: Metrics) -> dict[str, int]:
    return {item.name: getattr(metrics, item.name) for item in fields(metrics)}


def _node_object(node: Node) -> dict[str, Any]:
    return {
        "name": node.name,
        "own": _metrics_object(node.own),
        "total": _metrics_object(node.total),
        "children": [
            _node_object(child)
            for child in sorted(node.children.values(), key=lambda child: child.name)
        ],
    }


def measurement(
    root: Node, response: dict[str, Any], file_count: int
) -> dict[str, Any]:
    return {
        "format": OUTPUT_FORMAT,
        "runtime": response["runtime"],
        "vm": response["vm"],
        "source_count": file_count,
        "metrics": [item.name for item in fields(Metrics)],
        "tree": _node_object(root),
    }


def render_json(
    root: Node,
    response: dict[str, Any],
    file_count: int,
    file: IO[str] | None = None,
) -> None:
    output = file or sys.stdout
    json.dump(measurement(root, response, file_count), output, indent=2, sort_keys=True)
    output.write("\n")


def load_history(response: dict[str, Any], *, root: Path = ROOT) -> History:
    def git(*arguments: str) -> bytes:
        try:
            result = subprocess.run(
                ["git", *arguments], cwd=root, capture_output=True, check=False
            )
        except OSError as error:
            raise AnalysisError(f"cannot read size history: {error}") from error
        if result.returncode:
            detail = result.stderr.decode(errors="replace").strip()
            raise AnalysisError(f"cannot read size history: {detail}")
        return result.stdout

    # HEAD is not its own history, even when its committed tree has a note.
    ancestors = git("rev-list", "--topo-order", "HEAD").decode("ascii").splitlines()[1:]
    notes = {
        commit: blob
        for blob, commit in (
            line.split()
            for line in git("notes", f"--ref={NOTES_REF}", "list")
            .decode("ascii")
            .splitlines()
        )
    }
    history = History(ancestors=len(ancestors))
    metric_keys = {item.name for item in fields(Metrics)}

    def visit(
        value: Any, path: tuple[str, ...], nodes: dict[tuple[str, ...], Metrics]
    ) -> Metrics:
        node = _exact_object(
            value, {"name", "own", "total", "children"}, "history node"
        )
        name = node["name"]
        if (
            not isinstance(name, str)
            or not name
            or "/" in name
            or (not path and name != "poincare")
            or path in nodes
        ):
            raise AnalysisError("invalid or duplicate history path")
        counts = {}
        for kind in ("own", "total"):
            raw = _exact_object(node[kind], metric_keys, f"history {kind}")
            counts[kind] = Metrics(
                **{key: _integer(raw[key], f"history {key}") for key in metric_keys}
            )
        nodes[path] = counts["total"]
        if not isinstance(node["children"], list):
            raise AnalysisError("invalid history children")
        expected = counts["own"]
        for child in node["children"]:
            if not isinstance(child, dict) or not isinstance(child.get("name"), str):
                raise AnalysisError("invalid history child")
            expected = expected + visit(child, path + (child["name"],), nodes)
        if expected != counts["total"]:
            raise AnalysisError("history aggregation invariant failed")
        return expected

    for commit in ancestors:
        if commit not in notes:
            history.skipped["unnoted"] += 1
            continue
        # simplification: one Git read per note; use cat-file --batch for large histories.
        payload = git("cat-file", "blob", notes[commit])
        try:
            note = json.loads(payload)
            if not isinstance(note, dict) or note.get("format") not in (
                "poincare-size-note/v1",
                "poincare-size-note/v2",
            ):
                raise AnalysisError("unsupported size note format")
            if note.get("commit") != commit:
                raise AnalysisError("size note commit does not match its attachment")
            if "measurement" not in note:
                raise AnalysisError("size note has no measurement field")
            data = note["measurement"]
            if data is None and isinstance(note.get("error"), str) and note["error"]:
                history.skipped["unavailable"] += 1
                continue
            if not isinstance(data, dict) or note.get("error") is not None:
                raise AnalysisError("invalid size note measurement/error")
            if (
                data.get("format") != OUTPUT_FORMAT
                or data.get("runtime") != response["runtime"]
                or data.get("vm") != response["vm"]
            ):
                history.skipped["incompatible format/runtime/VM"] += 1
                continue
            metrics = data.get("metrics")
            if (
                not isinstance(metrics, list)
                or not all(isinstance(key, str) for key in metrics)
                or len(metrics) != len(metric_keys)
                or set(metrics) != metric_keys
            ):
                raise AnalysisError("invalid history metric list")
            _integer(data.get("source_count"), "history source count")
            nodes: dict[tuple[str, ...], Metrics] = {}
            visit(data.get("tree"), (), nodes)
        except (AnalysisError, ValueError, RecursionError) as error:
            history.skipped["invalid"] += 1
            history.warnings.append(f"{commit[:12]}: {error}")
            continue
        history.samples.append(nodes)
    return history


def distribution(
    value: int | float, samples: Iterable[int | float]
) -> dict[str, float] | None:
    values = sorted(samples)
    if not values:
        return None
    q1, median, q3 = (
        quantiles(values, n=4, method="inclusive")
        if len(values) > 1
        else [values[0]] * 3
    )
    return {
        "n": len(values),
        "percentile": 100
        * (
            sum(sample < value for sample in values)
            + sum(sample == value for sample in values) / 2
        )
        / len(values),
        "median": median,
        "q1": q1,
        "q3": q3,
        "min": values[0],
        "max": values[-1],
    }


_BAR_EIGHTHS = "▏▎▍▌▋▊▉"
_SPARK_LEVELS = "▁▂▃▄▅▆▇█"


def _bar(fraction: float, cells: int, align: str = "left") -> str:
    eighths = int(max(0.0, min(1.0, fraction)) * cells * 8)
    full, part = divmod(eighths, 8)
    filled = "█" * full + (_BAR_EIGHTHS[part - 1] if part else "")
    return filled.ljust(cells) if align == "left" else filled.rjust(cells)


def _sparkline(values: Iterable[int | float], width: int) -> str:
    series = list(values)
    if not series or width < 1:
        return ""
    if len(series) > width:
        series = [
            max(
                series[
                    bucket * len(series) // width : (bucket + 1) * len(series) // width
                ]
            )
            for bucket in range(width)
        ]
    low, high = min(series), max(series)
    if low == high:
        # Flat series sit mid-height unless they are zero.
        return (_SPARK_LEVELS[0] if high == 0 else _SPARK_LEVELS[3]) * len(series)
    return "".join(
        _SPARK_LEVELS[round(7 * (value - low) / (high - low))] for value in series
    )


def _display_children(
    node: Node, path: tuple[str, ...]
) -> Iterable[tuple[str, Node, tuple[str, ...]]]:
    for child in node.children.values():
        name = child.name
        child_path = path + (child.name,)
        while (
            child.own.empty()
            and len(child.children) == 1
            and child_path not in (("config",), ("plugins",))
            and not (len(child_path) == 2 and child_path[0] == "plugins")
        ):
            child = next(iter(child.children.values()))
            name += "/" + child.name
            child_path += (child.name,)
        yield name, child, child_path


def _display_rows(
    root: Node, metric: str, depth: int | None
) -> list[tuple[Node, Node | None, int, tuple[str, ...], tuple[bool, ...]]]:
    rows: list[tuple[Node, Node | None, int, tuple[str, ...], tuple[bool, ...]]] = [
        (root, None, 0, (), ())
    ]
    index = 0
    while index < len(rows):
        node, _, level, path, branches = rows[index]
        if depth is None or level < depth:
            children = sorted(
                _display_children(node, path),
                key=lambda item: (-getattr(item[1].total, metric), item[0]),
            )
            rows[index + 1 : index + 1] = [
                (
                    child,
                    node,
                    level + 1,
                    child_path,
                    branches + (child_index < len(children) - 1,),
                )
                for child_index, (_, child, child_path) in enumerate(children)
            ]
        index += 1
    return rows


def render(
    root: Node,
    runtime: dict[str, str],
    file_count: int,
    metric: str,
    depth: int | None,
    all_metrics: bool = False,
    file: IO[str] | None = None,
    width: int | None = None,
    history: History | None = None,
) -> None:
    from rich.console import Console
    from rich.text import Text

    selected = METRIC_NAMES[metric]
    labels = {
        "bytecodes": "BC",
        "functions": "Fn",
        "decisions": "Dec",
        "calls": "Call",
        "closures": "Clos",
        "tables": "Tbl",
        "global_reads": "GRead",
        "global_writes": "GWrite",
        "upvalue_reads": "URead",
        "upvalue_writes": "UWrite",
    }
    columns = (
        [item.name for item in fields(Metrics)]
        if all_metrics
        else ["bytecodes", "decisions", "functions", "tables", "calls"]
    )
    if selected not in columns:
        columns.append(selected)
    console = Console(file=file, width=width, color_system=None if file else "auto")
    graphs = console.is_terminal and console.width >= GRAPH_MIN_WIDTH
    console.print(
        f"{runtime['version']} {runtime['arch']} | {file_count} Lua files | metric={metric}",
        style="bold",
        markup=False,
    )
    if history is not None:
        console.print()
        sample_count = len(history.samples)
        console.print(
            f"History: {sample_count} comparable measurements from "
            f"{history.ancestors} earlier commits",
            style="bold",
            markup=False,
        )
        if history.skipped:
            reasons = {
                "incompatible format/runtime/VM": "incompatible",
                "invalid": "invalid",
                "unavailable": "unavailable",
                "unnoted": (
                    "without a note"
                    if history.skipped["unnoted"] == 1
                    else "without notes"
                ),
            }
            console.print(
                "Skipped commits: "
                + ", ".join(
                    f"{count} {reasons.get(reason, reason)}"
                    for reason, count in sorted(history.skipped.items())
                ),
                style="dim",
                markup=False,
            )
        for warning in history.warnings:
            console.print(f"Warning: {warning}", style="yellow", markup=False)
        if history.samples:
            console.print()
            console.print(
                "P is the percentile among earlier measurements "
                "(P50 is typical; higher is larger).\n"
                "Samples include only commits containing that path; "
                "share comparisons omit zero baselines.",
                style="dim italic",
                markup=False,
            )
        else:
            console.print(
                "No comparable history; showing current values only.",
                style="dim italic",
                markup=False,
            )
        console.print()

    def number(value: float) -> str:
        return f"{value:,.2f}".rstrip("0").rstrip(".")

    def rank(stats: dict[str, float] | None) -> str:
        assert stats is not None
        percentile = f"{stats['percentile']:.1f}".rstrip("0").rstrip(".")
        return f"P{percentile}"

    def print_detail(prefix: str, text: str | Text, style: str | None = None) -> None:
        if isinstance(text, str):
            content = Text(text, style=style) if style else Text(text)
        else:
            content = text
        lines = (
            content.wrap(console, max(1, console.width - len(prefix)))
            if history and history.samples
            else [content]
        )
        for line in lines:
            output = Text(prefix, style="dim")
            output.append_text(line)
            console.print(output, overflow="fold", markup=False)

    paths: dict[int, tuple[str, ...]] = {}
    for node, parent, level, path, branches in _display_rows(root, selected, depth):
        paths[id(node)] = path
        parent_value = (
            getattr(parent.total, selected) if parent else getattr(root.total, selected)
        )
        value = getattr(node.total, selected)
        root_value = getattr(root.total, selected)
        percentage = lambda numerator, denominator: (
            "n/a" if denominator == 0 else f"{100 * numerator / denominator:.1f}%"
        )
        logical = "/".join((root.name,) + path)
        guide = "".join("│   " if continued else "    " for continued in branches[:-1])
        branch = "" if not branches else "├── " if branches[-1] else "└── "
        detail = (
            "    " if not branches else guide + ("│   " if branches[-1] else "    ")
        )
        path_text = Text(guide + branch, style="dim")
        path_text.append(logical, style="bold")
        console.print(path_text, overflow="fold", markup=False)
        past = (
            [sample for sample in history.samples if path in sample] if history else []
        )
        stats = (
            {
                column: distribution(
                    getattr(node.total, column),
                    (getattr(sample[path], column) for sample in past),
                )
                for column in columns
            }
            if history and history.samples
            else {}
        )
        details = Text()
        for index, column in enumerate(columns):
            if index:
                details.append("  ")
            style = "bold cyan" if column == selected else None
            details.append(
                f"{labels[column]}={getattr(node.total, column):,}", style=style
            )
            if column == selected and stats.get(column):
                details.append(f" ({rank(stats[column])})", style=style)
        for label, denominator, denominator_path in (
            ("parent", parent_value, paths[id(parent)] if parent else ()),
            ("root", root_value, ()),
        ):
            details.append("  ")
            details.append(
                f"{label}={percentage(value, denominator)}",
                style="dim",
            )
            if stats:
                share_stats = (
                    distribution(
                        100 * value / denominator,
                        (
                            100
                            * getattr(sample[path], selected)
                            / getattr(sample[denominator_path], selected)
                            for sample in past
                            if getattr(sample[denominator_path], selected)
                        ),
                    )
                    if denominator
                    else None
                )
                if share_stats:
                    context = [rank(share_stats)]
                    if share_stats["n"] != len(past):
                        context.append(f"{share_stats['n']:.0f} samples")
                    details.append(f" ({'; '.join(context)})", style="cyan")
                elif denominator and past:
                    details.append(" (no history)", style="dim italic")
        print_detail(detail, details)
        if graphs and root_value:
            cells = max(4, min(28, console.width - len(detail) - 2))
            bar = Text(detail, style="dim")
            if history is not None:
                bar.append(_bar(value / root_value, cells), style="green")
            else:
                # Right-align plain-mode bars: shared right edge, clear of the tree.
                bar.append(" " * (console.width - len(detail) - cells))
                bar.append(
                    _bar(value / root_value, cells, align="right"), style="green"
                )
            console.print(bar, overflow="fold", markup=False)
        if stats and history is not None:
            summary = stats[selected]
            if summary is None:
                text = f"{labels[selected]} history: no earlier samples for this path"
            else:
                formatted = {
                    key: number(summary[key])
                    for key in ("median", "q1", "q3", "min", "max")
                }
                samples = (
                    f"{len(past)} sample{'s' if len(past) != 1 else ''}"
                    if len(past) == len(history.samples)
                    else f"{len(past)} of {len(history.samples)} samples"
                )
                if len(past) == 1:
                    text = f"{labels[selected]} history ({samples}): only value {formatted['median']}"
                elif summary["min"] == summary["max"]:
                    text = f"{labels[selected]} history ({samples}): {formatted['median']} throughout"
                else:
                    text = (
                        f"{labels[selected]} history ({samples}): median {formatted['median']}; "
                        f"middle 50% {formatted['q1']}-{formatted['q3']}; "
                        f"range {formatted['min']}-{formatted['max']}"
                    )
            print_detail(detail, text, style="dim italic")
            if graphs and past:
                # Samples arrive newest-first; draw oldest to current, left to right.
                series = [getattr(sample[path], selected) for sample in reversed(past)]
                series.append(value)
                annotation = f"{number(series[0])} → {number(series[-1])}"
                cells = max(
                    8,
                    min(
                        60,
                        console.width
                        - len(detail)
                        - len(labels[selected])
                        - len(annotation)
                        - 10,
                    ),
                )
                trend = Text(detail, style="dim")
                trend.append(f"{labels[selected]} trend ", style="dim italic")
                trend.append(_sparkline(series, cells), style="cyan")
                trend.append(f" {annotation}", style="dim italic")
                console.print(trend, overflow="fold", markup=False)
            if level == 0 and root.children and (depth is None or depth > 0):
                console.print()


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Analyse realised poincare LuaJIT bytecode"
    )
    parser.add_argument(
        "--metric",
        choices=METRIC_NAMES,
        default="bytecodes",
        help="metric used for sorting, parent/root percentages and history summary (default: bytecodes)",
    )
    depth = parser.add_mutually_exclusive_group()
    depth.add_argument(
        "--depth",
        type=int,
        default=3,
        help="maximum edges below the root; 0 shows only the root (default: 3)",
    )
    depth.add_argument("--full", action="store_true", help="show the complete tree")
    parser.add_argument(
        "--all-metrics", action="store_true", help="show every metric column"
    )
    output = parser.add_mutually_exclusive_group()
    output.add_argument(
        "--json",
        action="store_true",
        help="emit the complete measurement tree as versioned JSON",
    )
    output.add_argument(
        "--with-history",
        action="store_true",
        help="compare against local size notes on ancestors of HEAD, excluding HEAD; terminal output only",
    )
    parser.add_argument("--nvim", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--packpath", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.depth is not None and args.depth < 0:
        parser.error("--depth must be non-negative")
    if (args.nvim is None) != (args.packpath is None):
        parser.error("--nvim and --packpath must be supplied together")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        nvim, packpath = (args.nvim, args.packpath) if args.nvim else realise_outputs()
        sources = discover(packpath)
        if not sources:
            raise AnalysisError(f"no Lua sources found under {packpath}")
        response = probe(nvim, sources)
        tree = aggregate(sources, response)
        assert_aggregation(tree)
        if args.json:
            render_json(tree, response, len(sources))
        else:
            render(
                tree,
                response["runtime"],
                len(sources),
                args.metric,
                None if args.full else args.depth,
                args.all_metrics,
                history=load_history(response) if args.with_history else None,
            )
    except AnalysisError as error:
        print(f"size: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
