#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib
import io
import json
import math
import os
import subprocess
import sys
import tarfile
import tempfile
from collections import Counter
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path
from statistics import fmean, median, pstdev, quantiles
from typing import IO, Any

ROOT = Path(__file__).resolve().parent.parent
OUTPUT_FORMAT = "poincare-size/v1"
RAW_FORMAT = "poincare-size-raw/v1"
NOTES_REF = "refs/notes/poincare-size"
PERF_OUTPUT_FORMAT = "poincare-perf/v1"
PERF_RAW_FORMAT = "poincare-perf-raw/v1"
PERF_NOTES_REF = "refs/notes/poincare-perf"
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


class NoteError(RuntimeError):
    pass


@dataclass(frozen=True)
class Instruction:
    pc: int
    opcode: str
    target: int | None = None
    opcode_id: int = 0
    word: int = 0
    mode: int = 0
    line: int | None = None


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


Number = int | float
MetricValues = dict[str, Number]


@dataclass(frozen=True)
class MetricDescriptor:
    key: str
    label: str
    unit: str
    integer: bool = False


SIZE_METRIC_DESCRIPTORS = (
    MetricDescriptor("bytecodes", "BC", "bytecodes", True),
    MetricDescriptor("functions", "Fn", "functions", True),
    MetricDescriptor("decisions", "Dec", "decisions", True),
    MetricDescriptor("calls", "Call", "calls", True),
    MetricDescriptor("closures", "Clos", "closures", True),
    MetricDescriptor("tables", "Tbl", "tables", True),
    MetricDescriptor("global_reads", "GRead", "reads", True),
    MetricDescriptor("global_writes", "GWrite", "writes", True),
    MetricDescriptor("upvalue_reads", "URead", "reads", True),
    MetricDescriptor("upvalue_writes", "UWrite", "writes", True),
)
SIZE_METRICS = tuple(metric.key for metric in SIZE_METRIC_DESCRIPTORS)
PERF_METRIC_DESCRIPTORS = (
    MetricDescriptor("wall_ns", "Wall", "ns"),
    MetricDescriptor("profile_ns", "Profile", "ns"),
)
PERF_METRICS = tuple(metric.key for metric in PERF_METRIC_DESCRIPTORS)


def zero_metrics(keys: Iterable[str]) -> MetricValues:
    return dict.fromkeys(keys, 0)


def add_metrics(left: MetricValues, right: MetricValues) -> MetricValues:
    if left.keys() != right.keys():
        raise AnalysisError("metric sets do not match")
    result = {key: left[key] + right[key] for key in left}
    for key, value in result.items():
        _number(value, f"aggregated {key}")
    return result


def validate_metric_values(
    value: Any, descriptors: Iterable[MetricDescriptor], context: str
) -> MetricValues:
    metrics = tuple(descriptors)
    raw = _exact_object(value, {metric.key for metric in metrics}, context)
    return {
        metric.key: (
            _integer(raw[metric.key], f"{context} {metric.key}")
            if metric.integer
            else _number(raw[metric.key], f"{context} {metric.key}")
        )
        for metric in metrics
    }


@dataclass
class Node:
    name: str
    own: MetricValues = field(default_factory=dict)
    total: MetricValues = field(default_factory=dict)
    children: dict[str, Node] = field(default_factory=dict)


@dataclass
class History:
    samples: list[dict[tuple[str, ...], MetricValues]] = field(default_factory=list)
    ancestors: int = 0
    skipped: Counter[str] = field(default_factory=Counter)
    warnings: list[str] = field(default_factory=list)


def realise_outputs(root: Path) -> tuple[Path, Path]:
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
            command, cwd=root, text=True, capture_output=True, check=False
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


def _exact_object(value: Any, keys: set[str], context: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise AnalysisError(f"invalid {context} object")
    return value


def _integer(value: Any, context: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise AnalysisError(f"invalid {context}")
    return value


def _number(value: Any, context: str) -> Number:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
        raise AnalysisError(f"invalid {context}")
    if isinstance(value, float) and not math.isfinite(value):
        raise AnalysisError(f"invalid {context}")
    return value


def validate_raw(raw: Any) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    raw = _exact_object(
        raw, {"format", "collector", "manifest", "probe"}, "raw envelope"
    )
    if raw["format"] != RAW_FORMAT:
        raise AnalysisError("invalid raw envelope format")
    collector = _exact_object(
        raw["collector"], {"nvim", "adapter", "packpath"}, "collector"
    )

    def identity(value: Any, context: str) -> None:
        value = _exact_object(
            value,
            {"path", "resolved_path", "byte_length", "sha256"},
            context,
        )
        for key in ("path", "resolved_path"):
            if not isinstance(value[key], str) or not value[key] or "\x00" in value[key]:
                raise AnalysisError(f"invalid {context} {key}")
        _integer(value["byte_length"], f"{context} byte length")
        digest = value["sha256"]
        if (
            not isinstance(digest, str)
            or len(digest) != 64
            or any(character not in "0123456789abcdef" for character in digest)
        ):
            raise AnalysisError(f"invalid {context} SHA-256")

    identity(collector["nvim"], "collector nvim")
    identity(collector["adapter"], "collector adapter")
    packpath = _exact_object(
        collector["packpath"], {"path", "resolved_path"}, "collector packpath"
    )
    if not all(
        isinstance(packpath[key], str) and packpath[key] and "\x00" not in packpath[key]
        for key in packpath
    ):
        raise AnalysisError("invalid collector packpath")
    manifest = raw["manifest"]
    if not isinstance(manifest, list) or not manifest:
        raise AnalysisError("invalid raw manifest")
    logicals: set[tuple[str, ...]] = set()
    paths: set[str] = set()
    for expected_id, item in enumerate(manifest):
        item = _exact_object(
            item,
            {"id", "logical", "path", "resolved_path", "byte_length", "sha256"},
            "raw source",
        )
        if _integer(item["id"], "raw source id") != expected_id:
            raise AnalysisError("raw source IDs are not contiguous")
        logical = item["logical"]
        if (
            not isinstance(logical, list)
            or not logical
            or not all(
                isinstance(part, str)
                and part
                and "/" not in part
                and "\x00" not in part
                and part not in (".", "..")
                for part in logical
            )
        ):
            raise AnalysisError("invalid raw logical path")
        logical_key = tuple(logical)
        identity(
            {key: item[key] for key in ("path", "resolved_path", "byte_length", "sha256")},
            "raw source",
        )
        path = item["path"]
        if logical_key in logicals or path in paths:
            raise AnalysisError("duplicate raw source path")
        logicals.add(logical_key)
        paths.add(path)
    probe = _exact_object(
        raw["probe"],
        {"argv", "duration_ns", "returncode", "stdout", "stderr", "launch_error"},
        "probe",
    )
    if (
        not isinstance(probe["argv"], list)
        or not probe["argv"]
        or not all(isinstance(argument, str) and "\x00" not in argument for argument in probe["argv"])
        or not isinstance(probe["stdout"], str)
        or not isinstance(probe["stderr"], str)
    ):
        raise AnalysisError("invalid probe observation")
    _integer(probe["duration_ns"], "probe duration")
    if probe["returncode"] is None:
        if not isinstance(probe["launch_error"], str) or not probe["launch_error"]:
            raise AnalysisError("invalid probe launch failure")
        raise AnalysisError(f"cannot launch Neovim bytecode probe: {probe['launch_error']}")
    if isinstance(probe["returncode"], bool) or not isinstance(probe["returncode"], int):
        raise AnalysisError("invalid probe return code")
    if probe["launch_error"] is not None:
        raise AnalysisError("invalid probe launch error")
    if probe["returncode"]:
        detail = probe["stderr"].strip() or probe["stdout"].strip()
        raise AnalysisError(f"Neovim bytecode probe failed: {detail}")
    try:
        decoder = json.JSONDecoder()
        response, end = decoder.raw_decode(probe["stdout"])
        if probe["stdout"][end:].strip():
            raise ValueError("trailing output")
    except (json.JSONDecodeError, ValueError) as error:
        raise AnalysisError("bytecode probe did not return one JSON document") from error
    return manifest, validate_response(response, manifest)


def validate_response(response: Any, sources: list[dict[str, Any]]) -> dict[str, Any]:
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
    expected = {source["id"] for source in sources}
    seen: set[int] = set()
    by_id: dict[int, dict[str, Any]] = {}
    for item in items:
        if not isinstance(item, dict) or set(item) not in (
            {"id", "bytecode_dump", "prototypes"},
            {"id", "error"},
        ):
            raise AnalysisError("invalid source result object")
        source_id = _integer(item["id"], "source id")
        if source_id not in expected or source_id in seen:
            raise AnalysisError(f"unexpected or duplicate source id {source_id}")
        seen.add(source_id)
        if "error" in item:
            if not isinstance(item["error"], str) or not item["error"]:
                raise AnalysisError(f"invalid error for source {source_id}")
            by_id[source_id] = item
            continue
        prototypes = item["prototypes"]
        bytecode_dump = item["bytecode_dump"]
        if (
            not isinstance(bytecode_dump, str)
            or len(bytecode_dump) < 6
            or len(bytecode_dump) % 2
            or any(character not in "0123456789abcdef" for character in bytecode_dump)
            or not bytecode_dump.startswith("1b4c4a")
        ):
            raise AnalysisError(f"invalid bytecode dump for source {source_id}")
        if not isinstance(prototypes, list) or not prototypes:
            raise AnalysisError(f"invalid prototypes for source {source_id}")
        for prototype_id, prototype in enumerate(prototypes):
            prototype = _exact_object(
                prototype,
                {"id", "parent_id", "gcconst_index", "info", "instructions"},
                "prototype",
            )
            if _integer(prototype["id"], "prototype id") != prototype_id:
                raise AnalysisError("prototype IDs are not contiguous")
            parent_id = prototype["parent_id"]
            gcconst_index = prototype["gcconst_index"]
            if prototype_id == 0:
                if parent_id is not None or gcconst_index is not None:
                    raise AnalysisError("invalid root prototype hierarchy")
            elif (
                isinstance(parent_id, bool)
                or not isinstance(parent_id, int)
                or parent_id < 0
                or parent_id >= prototype_id
                or _integer(gcconst_index, "prototype GC constant index", 1) < 1
                or gcconst_index > prototypes[parent_id]["info"]["gcconsts"]
            ):
                raise AnalysisError("invalid prototype hierarchy")
            info = prototype["info"]
            if not isinstance(info, dict) or not all(
                isinstance(key, str)
                and isinstance(value, (str, int, float, bool))
                and (not isinstance(value, float) or math.isfinite(value))
                for key, value in info.items()
            ):
                raise AnalysisError("invalid prototype info")
            required_info = {
                "bytecodes", "gcconsts", "nconsts", "params", "stackslots",
                "upvalues", "isvararg",
            }
            if not required_info <= info.keys():
                raise AnalysisError("incomplete prototype info")
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
                    {"pc", "opcode", "opcode_id", "word", "mode", "line"},
                    {"pc", "opcode", "opcode_id", "word", "mode", "line", "target"},
                ):
                    raise AnalysisError("invalid instruction object")
                if _integer(instruction["pc"], "instruction pc", 1) != pc:
                    raise AnalysisError("instruction PCs are not contiguous")
                opcode = instruction["opcode"]
                if not isinstance(opcode, str) or opcode not in KNOWN_OPS:
                    raise AnalysisError("invalid instruction opcode")
                opcode_id = _integer(instruction["opcode_id"], "instruction opcode ID")
                if opcode_id >= len(opcodes) or opcodes[opcode_id] != opcode:
                    raise AnalysisError("instruction opcode ID does not match opcode")
                word = _integer(instruction["word"], "instruction word")
                if word > 0xFFFFFFFF or word & 0xFF != opcode_id:
                    raise AnalysisError("invalid instruction word")
                _integer(instruction["mode"], "instruction mode")
                if instruction["line"] is not None and (
                    isinstance(instruction["line"], bool)
                    or not isinstance(instruction["line"], int)
                ):
                    raise AnalysisError("invalid instruction line")
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
                Instruction(
                    item["pc"],
                    item["opcode"],
                    item.get("target"),
                    item["opcode_id"],
                    item["word"],
                    item["mode"],
                    item["line"],
                )
                for item in instructions
            ]
        by_id[source_id] = item
    missing = expected - seen
    if missing:
        raise AnalysisError(f"bytecode response omitted source IDs: {sorted(missing)}")
    response["sources"] = by_id
    return response


def select_size_sources(
    manifest: list[dict[str, Any]], *, include_tests: bool = False
) -> list[dict[str, Any]]:
    selected: list[dict[str, Any]] = []
    for source in manifest:
        logical = source["logical"]
        if (
            logical[0] not in ("config", "plugins")
            or (logical[0] == "config" and len(logical) < 2)
            or (logical[0] == "plugins" and len(logical) < 3)
        ):
            raise AnalysisError("invalid size logical path")
        if include_tests or "tests" not in logical[2:-1]:
            selected.append(source)
    if not selected:
        raise AnalysisError("no Lua sources selected for size measurement")
    return selected


def process_size_raw(
    raw: Any, *, include_tests: bool = False
) -> tuple[list[dict[str, Any]], dict[str, Any], Node]:
    manifest, response = validate_raw(raw)
    selected = select_size_sources(manifest, include_tests=include_tests)
    errors = [
        f"{source['path']}: {response['sources'][source['id']]['error']}"
        for source in selected
        if "error" in response["sources"][source["id"]]
    ]
    if errors:
        raise AnalysisError("Lua compilation failed:\n" + "\n".join(errors))
    tree = aggregate("poincare", selected, response)
    assert_aggregation(tree)
    return selected, response, tree


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


def prototype_metrics(instructions: list[Instruction]) -> MetricValues:
    blocks = build_cfg(instructions)
    opcodes = [instruction.opcode for instruction in instructions]
    return {
        "bytecodes": len(instructions),
        "functions": 1,
        "decisions": sum(max(0, len(block.successors) - 1) for block in blocks),
        "calls": sum(
            opcode in {"CALL", "CALLM", "CALLT", "CALLMT", "ITERC", "ITERN"}
            for opcode in opcodes
        ),
        "closures": opcodes.count("FNEW"),
        "tables": sum(opcode in {"TNEW", "TDUP"} for opcode in opcodes),
        "global_reads": opcodes.count("GGET"),
        "global_writes": opcodes.count("GSET"),
        "upvalue_reads": opcodes.count("UGET"),
        "upvalue_writes": sum(
            opcode in {"USETV", "USETS", "USETN", "USETP"} for opcode in opcodes
        ),
    }


def aggregate_tree(
    name: str,
    descriptors: tuple[MetricDescriptor, ...],
    leaves: Iterable[tuple[tuple[str, ...], Any]],
) -> Node:
    if not name or "/" in name or "\x00" in name or name in (".", ".."):
        raise AnalysisError("invalid tree root name")
    keys = tuple(metric.key for metric in descriptors)
    root = Node(name, zero_metrics(keys), zero_metrics(keys))
    seen: set[tuple[str, ...]] = set()
    for path, raw_metrics in leaves:
        if (
            not path
            or path in seen
            or not all(
                isinstance(part, str)
                and part
                and "/" not in part
                and "\x00" not in part
                and part not in (".", "..")
                for part in path
            )
        ):
            raise AnalysisError("invalid or duplicate tree path")
        seen.add(path)
        metrics = validate_metric_values(raw_metrics, descriptors, "leaf metrics")
        node = root
        for part in path:
            node = node.children.setdefault(
                part, Node(part, zero_metrics(keys), zero_metrics(keys))
            )
        node.own = add_metrics(node.own, metrics)

    def total(node: Node) -> MetricValues:
        node.total = dict(node.own)
        for child in node.children.values():
            node.total = add_metrics(node.total, total(child))
        return node.total

    total(root)
    return root


def aggregate(
    name: str, sources: list[dict[str, Any]], response: dict[str, Any]
) -> Node:
    leaves: list[tuple[tuple[str, ...], MetricValues]] = []
    for source in sources:
        metrics = zero_metrics(SIZE_METRICS)
        for prototype in response["sources"][source["id"]]["prototypes"]:
            metrics = add_metrics(metrics, prototype_metrics(prototype["instructions"]))
        leaves.append((tuple(source["logical"]), metrics))
    return aggregate_tree(name, SIZE_METRIC_DESCRIPTORS, leaves)


def assert_aggregation(node: Node) -> MetricValues:
    expected = dict(node.own)
    for child in node.children.values():
        expected = add_metrics(expected, assert_aggregation(child))
    if expected != node.total:
        raise AnalysisError(f"aggregation invariant failed at {node.name}")
    return expected


def _metrics_close(
    left: MetricValues,
    right: MetricValues,
    descriptors: Iterable[MetricDescriptor],
) -> bool:
    return all(
        left[descriptor.key] == right[descriptor.key]
        if descriptor.integer
        else math.isclose(
            left[descriptor.key], right[descriptor.key], rel_tol=1e-12, abs_tol=1e-6
        )
        for descriptor in descriptors
    )


def _node_object(node: Node) -> dict[str, Any]:
    return {
        "name": node.name,
        "own": dict(node.own),
        "total": dict(node.total),
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
        "metrics": list(SIZE_METRICS),
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


def load_history(
    response: dict[str, Any],
    *,
    root: Path = ROOT,
    kind: MeasurementKind | None = None,
) -> History:
    kind = kind or SIZE_KIND
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
            for line in git("notes", f"--ref={kind.notes_ref}", "list")
            .decode("ascii")
            .splitlines()
        )
    }
    history = History(ancestors=len(ancestors))
    metric_keys: set[str] = {metric.key for metric in kind.metric_descriptors}

    def visit(
        value: Any, path: tuple[str, ...], nodes: dict[tuple[str, ...], MetricValues]
    ) -> MetricValues:
        node = _exact_object(
            value, {"name", "own", "total", "children"}, "history node"
        )
        name = node["name"]
        if (
            not isinstance(name, str)
            or not name
            or "/" in name
            or "\x00" in name
            or name in (".", "..")
            or (not path and name != kind.root_name)
            or path in nodes
        ):
            raise AnalysisError("invalid or duplicate history path")
        counts = {}
        for node_kind in ("own", "total"):
            counts[node_kind] = validate_metric_values(
                node[node_kind], kind.metric_descriptors, f"history {node_kind}"
            )
        nodes[path] = counts["total"]
        if not isinstance(node["children"], list):
            raise AnalysisError("invalid history children")
        expected = counts["own"]
        for child in node["children"]:
            if not isinstance(child, dict) or not isinstance(child.get("name"), str):
                raise AnalysisError("invalid history child")
            expected = add_metrics(expected, visit(child, path + (child["name"],), nodes))
        if not _metrics_close(expected, counts["total"], kind.metric_descriptors):
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
            if not isinstance(note, dict) or note.get("format") not in kind.note_formats:
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
            if data.get("format") != kind.measurement_format or any(
                data.get(key) != response.get(key) for key in kind.compatibility_keys
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
            _integer(data.get(kind.count_field), f"history {kind.count_field}")
            nodes: dict[tuple[str, ...], MetricValues] = {}
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
    node: Node,
    path: tuple[str, ...],
    collapse_boundaries: frozenset[tuple[str, ...]] = frozenset(),
) -> Iterable[tuple[str, Node, tuple[str, ...]]]:
    for child in node.children.values():
        name = child.name
        child_path = path + (child.name,)
        while (
            not any(child.own.values())
            and len(child.children) == 1
            and child_path not in collapse_boundaries
        ):
            child = next(iter(child.children.values()))
            name += "/" + child.name
            child_path += (child.name,)
        yield name, child, child_path


def _display_rows(
    root: Node,
    metric: str,
    depth: int | None,
    collapse_boundaries: frozenset[tuple[str, ...]] = frozenset(),
) -> list[tuple[Node, Node | None, int, tuple[str, ...], tuple[bool, ...]]]:
    rows: list[tuple[Node, Node | None, int, tuple[str, ...], tuple[bool, ...]]] = [
        (root, None, 0, (), ())
    ]
    index = 0
    while index < len(rows):
        node, _, level, path, branches = rows[index]
        if depth is None or level < depth:
            children = sorted(
                _display_children(node, path, collapse_boundaries),
                key=lambda item: (-item[1].total[metric], item[0]),
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
    collapse_boundaries: frozenset[tuple[str, ...]] = frozenset(),
    descriptors: tuple[MetricDescriptor, ...] = SIZE_METRIC_DESCRIPTORS,
    default_columns: tuple[str, ...] = (
        "bytecodes", "decisions", "functions", "tables", "calls"
    ),
    heading: str | None = None,
    show_own: bool = False,
    repeated_statistics: dict[tuple[str, ...], dict[str, Any]] | None = None,
) -> None:
    from rich.console import Console
    from rich.text import Text

    by_key = {descriptor.key: descriptor for descriptor in descriptors}
    selected = METRIC_NAMES.get(metric, metric)
    if selected not in by_key:
        raise AnalysisError(f"unknown metric {metric}")
    labels = {key: descriptor.label for key, descriptor in by_key.items()}
    columns: list[str] = (
        list(by_key)
        if all_metrics
        else list(default_columns)
    )
    if selected not in columns:
        columns.append(selected)
    console = Console(file=file, width=width, color_system=None if file else "auto")
    graphs = console.is_terminal and console.width >= GRAPH_MIN_WIDTH
    console.print(
        heading
        or f"{runtime['version']} {runtime['arch']} | {file_count} Lua files | metric={metric}",
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

    def number(value: float, unit: str | None = None) -> str:
        if unit == "ns":
            return f"{value / 1_000_000:,.3f}".rstrip("0").rstrip(".") + " ms"
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
    for node, parent, level, path, branches in _display_rows(
        root, selected, depth, collapse_boundaries
    ):
        paths[id(node)] = path
        parent_value = (
            parent.total[selected] if parent else root.total[selected]
        )
        value = node.total[selected]
        root_value = root.total[selected]
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
                    node.total[column],
                    (sample[path][column] for sample in past),
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
                f"{labels[column]}={number(node.total[column], by_key[column].unit)}", style=style
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
                            * sample[path][selected]
                            / sample[denominator_path][selected]
                            for sample in past
                            if sample[denominator_path][selected]
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
        if show_own and any(node.own.values()):
            own = Text("Self: ", style="dim")
            own.append(
                ", ".join(
                    f"{labels[column]}={number(node.own[column], by_key[column].unit)}"
                    for column in columns
                    if node.own[column]
                )
            )
            print_detail(detail, own)
        repeated = repeated_statistics.get(path) if repeated_statistics else None
        if repeated and selected in repeated:
            summary = repeated[selected]
            spread = "single observation; spread unavailable" if summary["n"] == 1 else (
                f"median {number(summary['median'], by_key[selected].unit)}; "
                f"q1/q3 {number(summary['q1'], by_key[selected].unit)}/"
                f"{number(summary['q3'], by_key[selected].unit)}; "
                f"min/max {number(summary['min'], by_key[selected].unit)}/"
                f"{number(summary['max'], by_key[selected].unit)}; "
                f"stddev {number(summary['stddev'], by_key[selected].unit)}"
            )
            print_detail(
                detail,
                f"{labels[selected]} repeats: n={summary['n']}; mean "
                f"{number(summary['mean'], by_key[selected].unit)}; {spread}",
                style="dim italic",
            )
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
                    key: number(summary[key], by_key[selected].unit)
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
                series = [sample[path][selected] for sample in reversed(past)]
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


def parse_size_args(argv: list[str] | None = None) -> argparse.Namespace:
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
    output.add_argument(
        "--raw", action="store_true", help="emit the unprocessed collector envelope"
    )
    parser.add_argument(
        "--input",
        type=Path,
        help="read a raw collector envelope from PATH, or '-' for standard input",
    )
    parser.add_argument(
        "--include-tests",
        action="store_true",
        help="include Lua files below test directories in the processed measurement",
    )
    parser.add_argument("--nvim", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--packpath", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.depth is not None and args.depth < 0:
        parser.error("--depth must be non-negative")
    if (args.nvim is None) != (args.packpath is None):
        parser.error("--nvim and --packpath must be supplied together")
    if args.input is not None and (args.nvim is not None or args.raw):
        parser.error("--input cannot be combined with collector options or --raw")
    if args.include_tests and args.with_history:
        parser.error("--with-history requires the default source scope")
    return args


def _read_raw(path: Path) -> Any:
    try:
        if str(path) == "-":
            return json.load(sys.stdin)
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise AnalysisError(f"cannot read raw input {path}: {error}") from error


def _safe_name(value: Any, context: str) -> str:
    if (
        not isinstance(value, str)
        or not value
        or value in (".", "..")
        or any(character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for character in value)
    ):
        raise AnalysisError(f"invalid {context}")
    return value


def _validate_bench_config(config: Any, context: str) -> str:
    if not isinstance(config, dict):
        raise AnalysisError(f"invalid {context} object")
    allowed = {"name", "description", "steps", "args", "setup"}
    if set(config) - allowed or not {"name", "description", "steps"} <= set(config):
        raise AnalysisError(f"invalid {context} object")
    name = _safe_name(config["name"], f"{context} name")
    if not isinstance(config["description"], str) or not config["description"].strip():
        raise AnalysisError(f"invalid bench {name} description")
    if "setup" in config and (not isinstance(config["setup"], str) or not config["setup"].strip()):
        raise AnalysisError(f"invalid bench {name} setup")
    args = config.get("args", [])
    forbidden_exact = {"-i", "-n", "--headless", "--clean", "--embed", "--listen"}
    forbidden_prefixes = ("-u", "-c", "-l", "+", "--cmd", "--startuptime")
    if not isinstance(args, list) or any(
        not isinstance(argument, str)
        or not argument
        or "\0" in argument
        or argument in forbidden_exact
        or argument.startswith(forbidden_prefixes)
        for argument in args
    ):
        raise AnalysisError(f"invalid bench {name} args")
    steps = config["steps"]
    if not isinstance(steps, list) or not steps:
        raise AnalysisError(f"bench {name} must have steps")
    step_names: set[str] = set()
    for index, step in enumerate(steps):
        step = _exact_object(step, {"name", "lua"}, f"bench {name} step {index}")
        step_name = _safe_name(step["name"], f"bench {name} step name")
        if step_name in step_names:
            raise AnalysisError(f"duplicate step {step_name} in bench {name}")
        step_names.add(step_name)
        if not isinstance(step["lua"], str) or not step["lua"].strip():
            raise AnalysisError(f"invalid Lua for bench {name} step {step_name}")
    return name


def load_benches(directory: Path, selected: list[str] | None = None) -> list[dict[str, Any]]:
    try:
        paths = sorted(directory.glob("*.json"))
    except OSError as error:
        raise AnalysisError(f"cannot list benches {directory}: {error}") from error
    benches: list[dict[str, Any]] = []
    names: set[str] = set()
    for path in paths:
        try:
            content = path.read_text(encoding="utf-8")
            config = json.loads(content)
        except (OSError, json.JSONDecodeError) as error:
            raise AnalysisError(f"cannot read bench {path}: {error}") from error
        name = _validate_bench_config(config, f"bench {path.name}")
        if path.stem != name:
            raise AnalysisError(f"bench name {name!r} does not match {path.name}")
        if name in names:
            raise AnalysisError(f"duplicate bench name {name}")
        names.add(name)
        benches.append({
            "name": name,
            "path": str(path),
            "sha256": hashlib.sha256(content.encode()).hexdigest(),
            "content": content,
            "config": config,
        })
    requested = selected or [bench["name"] for bench in benches]
    if not requested:
        raise AnalysisError("no benches selected")
    if len(requested) != len(set(requested)):
        raise AnalysisError("duplicate --bench selection")
    by_name = {bench["name"]: bench for bench in benches}
    missing = [name for name in requested if name not in by_name]
    if missing:
        raise AnalysisError("unknown bench: " + ", ".join(missing))
    return [by_name[name] for name in requested]


def _summary(values: list[Number]) -> dict[str, Number | None]:
    ordered = sorted(values)
    q1, q3 = (quantiles(ordered, n=4, method="inclusive")[::2] if len(ordered) > 1 else (None, None))
    return {
        "n": len(values),
        "mean": fmean(values),
        "median": median(values),
        "q1": q1,
        "q3": q3,
        "min": ordered[0],
        "max": ordered[-1],
        "stddev": pstdev(values) if len(values) > 1 else None,
    }


def _trace_run(observation: dict[str, Any]) -> tuple[dict[tuple[str, ...], Number], dict[str, Any]]:
    try:
        trace = json.loads(observation["trace"])
    except (TypeError, json.JSONDecodeError) as error:
        raise AnalysisError("invalid or missing trace JSON") from error
    if not isinstance(trace, dict) or trace.get("protocol") != "poincare-perf-trace/v1":
        raise AnalysisError("invalid trace protocol")
    if trace.get("ok") is not True or trace.get("startup_error") is not None:
        raise AnalysisError(f"workload trace failed: {trace.get('error') or trace.get('startup_error')}")
    events = trace.get("events")
    if not isinstance(events, list):
        raise AnalysisError("invalid trace events")
    by_id: dict[int, dict[str, Any]] = {}
    paths: dict[int, tuple[str, ...]] = {}
    own: dict[tuple[str, ...], Number] = {}
    active: list[dict[str, Any]] = []
    previous_begin = -1
    for index, event in enumerate(events):
        if not isinstance(event, dict):
            raise AnalysisError("invalid trace event")
        event_id = _integer(event.get("id"), "trace event id", 1)
        if event_id in by_id:
            raise AnalysisError("duplicate trace event id")
        name = event.get("name")
        if not isinstance(name, str) or not name or "/" in name or "\0" in name:
            raise AnalysisError("invalid trace event name")
        begin = _integer(event.get("begin_ns"), "trace begin")
        end = _integer(event.get("end_ns"), "trace end")
        duration = _integer(event.get("duration_ns"), "trace duration")
        if end < begin or duration != end - begin or begin < previous_begin or event.get("ok") is not True:
            raise AnalysisError("invalid trace event interval")
        previous_begin = begin
        while active and begin >= active[-1]["end_ns"]:
            active.pop()
        parent_id = event.get("parent_id")
        expected_parent = active[-1]["id"] if active else None
        if parent_id != expected_parent or (active and end > active[-1]["end_ns"]):
            raise AnalysisError("trace events are not strictly nested")
        parent_path = paths[parent_id] if parent_id is not None else ()
        path = parent_path + (name,)
        paths[event_id] = path
        by_id[event_id] = event
        active.append(event)
    child_time = {event_id: 0 for event_id in by_id}
    for event in by_id.values():
        if event.get("parent_id") is not None:
            child_time[event["parent_id"]] += event["duration_ns"]
    for event_id, event in by_id.items():
        exclusive = event["duration_ns"] - child_time[event_id]
        if exclusive < 0:
            raise AnalysisError("trace children exceed parent duration")
        own[paths[event_id]] = own.get(paths[event_id], 0) + exclusive
    top_level = sum(event["duration_ns"] for event in by_id.values() if event.get("parent_id") is None)
    remainder = observation["wall_ns"] - top_level
    if remainder < 0:
        raise AnalysisError("trace duration exceeds external process wall time")
    own[("process-unattributed",)] = remainder
    return own, trace


def process_perf_raw(raw: Any) -> tuple[Node, dict[str, Any]]:
    raw = _exact_object(raw, {"format", "workloads", "collection", "collector", "observations"}, "perf raw envelope")
    if raw["format"] != PERF_RAW_FORMAT:
        raise AnalysisError("unsupported perf raw format")
    collection = _exact_object(
        raw["collection"],
        {"repeat", "warmups", "timeout_seconds", "schedule", "cache_policy", "wall_clock_scope"},
        "perf collection",
    )
    repeat = _integer(collection.get("repeat"), "repeat", 1)
    warmups = _integer(collection.get("warmups"), "warmups")
    timeout = _number(collection.get("timeout_seconds"), "timeout")
    if timeout <= 0:
        raise AnalysisError("timeout must be positive")
    if not isinstance(collection.get("cache_policy"), str) or not isinstance(collection.get("wall_clock_scope"), str):
        raise AnalysisError("invalid perf collection policy")
    workloads = raw["workloads"]
    if not isinstance(workloads, list) or not workloads:
        raise AnalysisError("invalid perf workloads")
    identities: dict[str, str] = {}
    configs: dict[str, dict[str, Any]] = {}
    for workload in workloads:
        workload = _exact_object(
            workload, {"name", "path", "sha256", "content", "config"}, "perf workload"
        )
        name = _safe_name(workload.get("name"), "perf workload name")
        if not isinstance(workload.get("path"), str) or "\0" in workload["path"]:
            raise AnalysisError(f"invalid workload path for {name}")
        digest = workload.get("sha256")
        content = workload.get("content")
        if not isinstance(content, str) or not isinstance(digest, str) or hashlib.sha256(content.encode()).hexdigest() != digest:
            raise AnalysisError(f"invalid workload hash for {name}")
        try:
            decoded = json.loads(content)
        except json.JSONDecodeError as error:
            raise AnalysisError(f"invalid workload content for {name}") from error
        if decoded != workload.get("config") or _validate_bench_config(decoded, f"raw bench {name}") != name or name in identities:
            raise AnalysisError(f"mismatched or duplicate workload {name}")
        identities[name] = digest
        configs[name] = decoded
    observations = raw["observations"]
    if not isinstance(observations, list):
        raise AnalysisError("invalid perf observations")
    expected = {
        (name, mode, iteration, iteration < warmups)
        for name in identities
        for mode in ("wall", "profile")
        for iteration in range(warmups + repeat)
    }
    expected_schedule = [
        {"workload": name, "mode": mode, "iteration": iteration, "warmup": iteration < warmups}
        for name in identities
        for mode in ("wall", "profile")
        for iteration in range(warmups + repeat)
    ]
    if collection.get("schedule") != expected_schedule:
        raise AnalysisError("invalid perf collection schedule")
    seen: dict[tuple[str, str, int, bool], dict[str, Any]] = {}
    runtime = None
    for observation in observations:
        observation = _exact_object(
            observation,
            {"workload", "workload_sha256", "mode", "iteration", "warmup",
             "started_at_unix_ns", "wall_ns", "argv", "cwd", "environment_policy",
             "returncode", "stdout", "stderr", "timed_out", "launch_error", "trace",
             "trace_read_error", "startuptime"},
            "perf observation",
        )
        name_value = observation.get("workload")
        mode_value = observation.get("mode")
        if not isinstance(name_value, str) or not isinstance(mode_value, str):
            raise AnalysisError("invalid perf attempt identity")
        name, mode = name_value, mode_value
        iteration = _integer(observation.get("iteration"), "iteration")
        warmup = observation.get("warmup")
        if not isinstance(warmup, bool):
            raise AnalysisError("invalid warmup flag")
        key = (name, mode, iteration, warmup)
        if key not in expected or key in seen or observation.get("workload_sha256") != identities.get(name):
            raise AnalysisError("unexpected, duplicate, or mismatched perf attempt")
        seen[key] = observation
        _integer(observation.get("started_at_unix_ns"), "attempt start timestamp")
        _number(observation.get("wall_ns"), "wall time")
        if (
            not isinstance(observation.get("argv"), list)
            or any(not isinstance(item, str) or "\0" in item for item in observation["argv"])
            or not isinstance(observation.get("cwd"), str)
            or not isinstance(observation.get("environment_policy"), dict)
            or not isinstance(observation.get("stdout"), str)
            or not isinstance(observation.get("stderr"), str)
        ):
            raise AnalysisError("invalid perf attempt metadata")
        returncode = observation.get("returncode")
        if isinstance(returncode, bool) or not isinstance(returncode, int):
            raise AnalysisError("invalid perf return code")
        if observation.get("returncode") != 0 or observation.get("timed_out") is not False or observation.get("launch_error") is not None or observation.get("trace_read_error") is not None:
            raise AnalysisError(f"failed perf attempt {name}/{mode}/{iteration}")
        _, trace = _trace_run(observation)
        steps = trace.get("steps")
        expected_steps = [step["name"] for step in configs[name]["steps"]]
        if (
            not isinstance(steps, list)
            or [step.get("name") for step in steps if isinstance(step, dict)] != expected_steps
            or any(not isinstance(step, dict) or step.get("ok") is not True for step in steps)
        ):
            raise AnalysisError("incomplete or failed workload steps")
        if runtime is None:
            runtime = trace.get("runtime")
        elif runtime != trace.get("runtime"):
            raise AnalysisError("runtime changed during perf collection")
    if set(seen) != expected:
        raise AnalysisError("incomplete perf attempt schedule")

    suite = Node("poincare", zero_metrics(PERF_METRICS), zero_metrics(PERF_METRICS))
    statistics: dict[str, Any] = {}
    node_statistics: dict[str, dict[str, Any]] = {}
    for name in identities:
        wall_runs = [seen[(name, "wall", i, False)]["wall_ns"] for i in range(warmups, warmups + repeat)]
        profile_observations = [seen[(name, "profile", i, False)] for i in range(warmups, warmups + repeat)]
        profile_runs = [observation["wall_ns"] for observation in profile_observations]
        run_own = [_trace_run(observation)[0] for observation in profile_observations]
        paths = set().union(*(run.keys() for run in run_own))
        leaves = []
        component_stats = {}
        for path in sorted(paths):
            values = [run.get(path, 0) for run in run_own]
            if path:
                leaves.append((path, {"wall_ns": 0, "profile_ns": fmean(values)}))
                totals = [
                    sum(value for candidate, value in run.items() if candidate[:len(path)] == path)
                    for run in run_own
                ]
                component_stats["/".join(path)] = {
                    "own": _summary(values),
                    "total": _summary(totals),
                }
                node_statistics["/".join((name,) + path)] = {
                    "profile_ns": _summary(totals)
                }
        workload = aggregate_tree(name, PERF_METRIC_DESCRIPTORS, leaves)
        workload.own["wall_ns"] = fmean(wall_runs)
        workload.own["profile_ns"] = 0
        workload.total = dict(workload.own)
        for child in workload.children.values():
            workload.total = add_metrics(workload.total, child.total)
        suite.children[name] = workload
        suite.total = add_metrics(suite.total, workload.total)
        statistics[name] = {
            "wall_ns": _summary(wall_runs),
            "profile_ns": _summary(profile_runs),
            "components_profile_ns": component_stats,
        }
        node_statistics[name] = {
            "wall_ns": statistics[name]["wall_ns"],
            "profile_ns": statistics[name]["profile_ns"],
        }
    return suite, {
        "format": PERF_OUTPUT_FORMAT,
        "runtime": runtime,
        "metrics": list(PERF_METRICS),
        "workload_count": len(workloads),
        "compatibility": {
            "workloads": identities,
            "harness_sha256": raw.get("collector", {}).get("harness", {}).get("sha256"),
            "host": raw.get("collector", {}).get("host"),
            "cache_policy": collection.get("cache_policy"),
            "environment_policy": observations[0].get("environment_policy") if observations else None,
            "runtime": runtime,
            "protocol": "poincare-perf-trace/v1",
        },
        "statistics": statistics,
        "node_statistics": node_statistics,
        "tree": _node_object(suite),
        "raw": raw,
    }


def parse_perf_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Benchmark the packaged poincare Neovim")
    parser.add_argument("--bench", action="append", help="select a workload by name; repeatable")
    parser.add_argument("--benches", type=Path, default=ROOT / "scripts" / "benches", help="workload JSON directory")
    parser.add_argument("--list", action="store_true", help="list validated workloads and exit")
    parser.add_argument("--repeat", type=int, default=10, help="scored attempts per mode and workload (default: 10)")
    parser.add_argument("--warmups", type=int, default=1, help="warm-up attempts per mode and workload (default: 1)")
    parser.add_argument("--timeout", type=float, default=30.0, help="per-process timeout in seconds (default: 30)")
    parser.add_argument("--metric", choices=PERF_METRICS, default="profile_ns", help="tree sorting and attribution metric")
    depth = parser.add_mutually_exclusive_group()
    depth.add_argument("--depth", type=int, default=3)
    depth.add_argument("--full", action="store_true")
    parser.add_argument("--all-metrics", action="store_true")
    output = parser.add_mutually_exclusive_group()
    output.add_argument("--json", action="store_true", help="emit processed JSON with complete raw evidence")
    output.add_argument("--raw", action="store_true", help="emit the complete collector envelope")
    output.add_argument("--with-history", action="store_true", help="compare compatible ancestor measurements")
    parser.add_argument("--input", type=Path, help="replay raw JSON from PATH or '-'")
    parser.add_argument("--nvim", type=Path, help="override the packaged executable for testing")
    args = parser.parse_args(argv)
    if args.repeat < 1 or args.warmups < 0:
        parser.error("--repeat must be positive and --warmups non-negative")
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be finite and positive")
    if args.depth is not None and args.depth < 0:
        parser.error("--depth must be non-negative")
    if args.input is not None and (args.raw or args.nvim is not None or args.list or args.bench):
        parser.error("--input cannot be combined with collection or selection options")
    return args


def perf_main(argv: list[str] | None = None, *, root: Path = ROOT) -> int:
    args = parse_perf_args(argv)
    try:
        if args.input is not None:
            raw = _read_raw(args.input)
        else:
            workloads = load_benches(args.benches, args.bench)
            if args.list:
                for workload in workloads:
                    print(f"{workload['name']}\t{workload['config']['description']}")
                return 0
            perf = importlib.import_module("scripts.perf" if __package__ else "perf")
            nvim = args.nvim or realise_outputs(root)[0]
            raw = perf.collect(nvim, workloads, repeat=args.repeat, warmups=args.warmups, timeout=args.timeout)
        if args.raw:
            json.dump(raw, sys.stdout, indent=2, sort_keys=True)
            sys.stdout.write("\n")
            return 0
        tree, data = process_perf_raw(raw)
        if args.json:
            json.dump(data, sys.stdout, indent=2, sort_keys=True)
            sys.stdout.write("\n")
        else:
            render(
                tree,
                {"version": "Neovim", "arch": "", "os": ""},
                data["workload_count"],
                args.metric,
                None if args.full else args.depth,
                args.all_metrics,
                history=load_history(data, root=root, kind=PERF_KIND) if args.with_history else None,
                descriptors=PERF_METRIC_DESCRIPTORS,
                default_columns=PERF_METRICS,
                show_own=True,
                repeated_statistics={
                    tuple(path.split("/")): stats
                    for path, stats in data["node_statistics"].items()
                },
                heading=(f"{data['workload_count']} workload means (not a contiguous run) | "
                         "Wall=uninstrumented process lifetime; Profile=instrumented process lifetime"),
            )
    except AnalysisError as error:
        print(f"perf: {error}", file=sys.stderr)
        return 1
    return 0


def size_main(argv: list[str] | None = None, *, root: Path = ROOT) -> int:
    args = parse_size_args(argv)
    try:
        if args.input is not None:
            raw = _read_raw(args.input)
        else:
            size = importlib.import_module("scripts.size" if __package__ else "size")
            nvim, packpath = (
                (args.nvim, args.packpath)
                if args.nvim
                else realise_outputs(root)
            )
            raw = size.collect(nvim, packpath)
        if args.raw:
            json.dump(raw, sys.stdout, indent=2, sort_keys=True)
            sys.stdout.write("\n")
            return 0
        sources, response, tree = process_size_raw(
            raw, include_tests=args.include_tests
        )
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
                history=load_history(response, root=root) if args.with_history else None,
                collapse_boundaries=frozenset(
                    {("config",), ("plugins",)}
                    | {
                        ("plugins", source["logical"][1])
                        for source in sources
                        if source["logical"][0] == "plugins"
                    }
                ),
            )
    except AnalysisError as error:
        print(f"size: {error}", file=sys.stderr)
        return 1
    return 0


@dataclass(frozen=True)
class MeasurementKind:
    name: str
    measurement_format: str
    note_formats: tuple[str, ...]
    note_format: str
    notes_ref: str
    analyser_entry: str
    metric_descriptors: tuple[MetricDescriptor, ...]
    root_name: str
    count_field: str
    compatibility_keys: tuple[str, ...]


SIZE_KIND = MeasurementKind(
    "size",
    OUTPUT_FORMAT,
    ("poincare-size-note/v1", "poincare-size-note/v2"),
    "poincare-size-note/v2",
    NOTES_REF,
    "scripts/size.py",
    SIZE_METRIC_DESCRIPTORS,
    "poincare",
    "source_count",
    ("runtime", "vm"),
)
PERF_KIND = MeasurementKind(
    "perf",
    PERF_OUTPUT_FORMAT,
    ("poincare-perf-note/v1",),
    "poincare-perf-note/v1",
    PERF_NOTES_REF,
    "scripts/perf.py",
    PERF_METRIC_DESCRIPTORS,
    "poincare",
    "workload_count",
    ("compatibility",),
)
JJ_ALIAS = [
    "util", "exec", "--", "sh", "-c",
    'exec python3 "$JJ_WORKSPACE_ROOT/scripts/size_note.py" jj-commit "$@"', "",
]


def _run(
    command: list[str], *, cwd: Path, check: bool = True, input: str | None = None
) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            command, cwd=cwd, text=True, input=input, capture_output=True, check=False
        )
    except OSError as error:
        raise NoteError(f"cannot run {command[0]}: {error}") from error
    if check and result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        raise NoteError(
            f"{' '.join(command)} failed" + (f": {detail}" if detail else "")
        )
    return result


def _git(
    arguments: list[str], *, root: Path, check: bool = True, input: str | None = None
) -> subprocess.CompletedProcess[str]:
    return _run(["git", *arguments], cwd=root, check=check, input=input)


def _resolve_commit(revision: str, root: Path) -> str:
    commit = _git(
        ["rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}"],
        root=root,
    ).stdout.strip()
    if not commit or any(character not in "0123456789abcdef" for character in commit):
        raise NoteError(f"git returned an invalid object ID for {revision!r}")
    return commit


def _has_note(commit: str, root: Path, kind: MeasurementKind) -> bool:
    result = _git(
        ["notes", f"--ref={kind.notes_ref}", "show", commit], root=root, check=False
    )
    if result.returncode not in (0, 1):
        detail = result.stderr.strip() or result.stdout.strip()
        raise NoteError(f"cannot inspect existing note for {commit}: {detail}")
    return result.returncode == 0


def _extract(
    commit: str,
    destination: Path,
    root: Path,
    paths: list[str] | None = None,
) -> None:
    command = ["git", "archive", "--format=tar", commit]
    if paths:
        command.extend(["--", *paths])
    try:
        result = subprocess.run(
            command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False
        )
    except OSError as error:
        raise NoteError("cannot run git archive: " + str(error)) from error
    if result.returncode:
        raise NoteError(
            "git archive failed: "
            + result.stderr.decode(errors="replace").strip()
        )
    try:
        # The committed tree is executable input and contains an intentional absolute symlink.
        with tarfile.open(fileobj=io.BytesIO(result.stdout), mode="r:") as archive:
            archive.extractall(destination, filter="fully_trusted")
    except (OSError, tarfile.TarError) as error:
        raise NoteError(f"cannot extract commit {commit}: {error}") from error


def _analyse(
    commit: str, analyser: str, root: Path, kind: MeasurementKind = SIZE_KIND
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix=f"poincare-{kind.name}-") as temporary:
        source = Path(temporary)
        _extract(commit, source, root)
        if not (source / "flake.nix").is_file():
            raise NoteError(f"commit {commit} has no flake.nix")
        if analyser != commit:
            _extract(analyser, source, root, ["scripts"])
        analyser_path = source / kind.analyser_entry
        if not analyser_path.is_file():
            raise NoteError(f"commit {commit} has no {kind.analyser_entry}")
        result = _run([sys.executable, str(analyser_path), "--json"], cwd=source)
        try:
            measurement_data = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise NoteError(f"{kind.analyser_entry} did not emit valid JSON") from error
    if (
        not isinstance(measurement_data, dict)
        or measurement_data.get("format") != kind.measurement_format
    ):
        raise NoteError(
            f"{kind.analyser_entry} did not emit {kind.measurement_format}"
        )
    return measurement_data


def _attach_note(
    commit: str,
    analyser: str,
    change_id: str | None,
    measurement_data: dict[str, Any] | None,
    error: str | None,
    *,
    root: Path,
    kind: MeasurementKind = SIZE_KIND,
    force: bool = False,
) -> None:
    payload = json.dumps(
        {
            "format": kind.note_format,
            "commit": commit,
            "jj_change_id": change_id,
            "analyser_commit": analyser,
            "measurement": measurement_data,
            "error": error,
        },
        indent=2,
        sort_keys=True,
    ) + "\n"
    arguments = ["notes", f"--ref={kind.notes_ref}", "add"]
    if force:
        arguments.append("--force")
    arguments.extend(["--file=-", commit])
    _git(arguments, root=root, input=payload)
    print(
        f"{kind.name}-note: attached {kind.notes_ref} to {commit[:12]}",
        file=sys.stderr,
    )


def record(
    revision: str,
    *,
    root: Path = ROOT,
    change_id: str | None = None,
    analyser_revision: str | None = None,
    force: bool = False,
    kind: MeasurementKind = SIZE_KIND,
) -> None:
    commit = _resolve_commit(revision, root)
    if not force and _has_note(commit, root, kind):
        print(f"{kind.name}-note: {commit[:12]} already has a measurement", file=sys.stderr)
        return
    print(f"{kind.name}-note: measuring {commit[:12]}", file=sys.stderr)
    analyser = _resolve_commit(analyser_revision or commit, root)
    _attach_note(
        commit, analyser, change_id, _analyse(commit, analyser, root, kind), None,
        root=root, kind=kind, force=force,
    )


def _jj_change_id(commit: str, root: Path) -> str | None:
    result = _run(
        [
            "jj", "--ignore-working-copy", "log", "--no-graph", "-r", commit,
            "-T", 'change_id ++ "\\n"',
        ],
        cwd=root,
        check=False,
    )
    lines = result.stdout.splitlines()
    return lines[0] if result.returncode == 0 and len(lines) == 1 else None


def backfill(
    base_revision: str,
    tip_revision: str,
    *,
    root: Path = ROOT,
    analyser_revision: str | None = None,
    include_base: bool = False,
    record_errors: bool = False,
    kind: MeasurementKind = SIZE_KIND,
) -> None:
    base = _resolve_commit(base_revision, root)
    tip = _resolve_commit(tip_revision, root)
    ancestry = _git(["merge-base", "--is-ancestor", base, tip], root=root, check=False)
    if ancestry.returncode == 1:
        raise NoteError(f"{base_revision!r} is not an ancestor of {tip_revision!r}")
    if ancestry.returncode:
        detail = ancestry.stderr.strip() or ancestry.stdout.strip()
        raise NoteError(f"cannot inspect the requested commit range: {detail}")
    commits = _git(
        ["rev-list", "--reverse", "--topo-order", f"{base}..{tip}"], root=root
    ).stdout.splitlines()
    if include_base:
        commits.insert(0, base)
    analyser = _resolve_commit(analyser_revision or tip, root)
    print(
        f"{kind.name}-note: backfilling {len(commits)} commits with analyser {analyser[:12]}",
        file=sys.stderr,
    )
    failures = 0
    for index, commit in enumerate(commits, 1):
        print(f"{kind.name}-note: [{index}/{len(commits)}]", file=sys.stderr)
        change_id = _jj_change_id(commit, root)
        try:
            record(
                commit, root=root, change_id=change_id,
                analyser_revision=analyser, kind=kind,
            )
        except NoteError as error:
            if not record_errors:
                raise
            failures += 1
            print(f"{kind.name}-note: unavailable: {error}", file=sys.stderr)
            _attach_note(
                commit, analyser, change_id, None, str(error), root=root, kind=kind
            )
    if failures:
        print(
            f"{kind.name}-note: recorded {failures} unavailable measurements",
            file=sys.stderr,
        )


def _jj_identity(root: Path) -> tuple[str, str]:
    lines = _run(
        [
            "jj", "log", "--no-graph", "-r", "@-", "-T",
            'commit_id ++ "\\n" ++ change_id ++ "\\n"',
        ],
        cwd=root,
    ).stdout.splitlines()
    if len(lines) != 2:
        raise NoteError("jj did not identify the commit created by jj commit")
    return lines[0], lines[1]


def jj_commit(arguments: list[str], *, root: Path = ROOT) -> int:
    try:
        result = subprocess.run(["jj", "commit", *arguments], cwd=root, check=False)
    except OSError as error:
        raise NoteError(f"cannot run jj commit: {error}") from error
    if result.returncode or any(argument in ("-h", "--help") for argument in arguments):
        return result.returncode
    commit, change_id = _jj_identity(root)
    record(commit, root=root, change_id=change_id)
    return 0


def _config_values(name: str, root: Path) -> list[str]:
    result = _git(["config", "--local", "--get-all", name], root=root, check=False)
    if result.returncode not in (0, 1):
        detail = result.stderr.strip() or result.stdout.strip()
        raise NoteError(f"cannot read git config {name}: {detail}")
    return result.stdout.splitlines()


def install(*, root: Path = ROOT) -> None:
    git_root = Path(_git(["rev-parse", "--show-toplevel"], root=root).stdout.strip()).resolve()
    jj_root = Path(_run(["jj", "workspace", "root"], cwd=root).stdout.strip()).resolve()
    jj_git_root = Path(_run(["jj", "git", "root"], cwd=root).stdout.strip()).resolve()
    if git_root != root.resolve() or jj_root != git_root:
        raise NoteError("run install from this repository's main jj workspace")
    if jj_git_root != (git_root / ".git").resolve():
        raise NoteError("the jj workspace must be colocated with Git")
    hook = root / ".githooks" / "post-commit"
    if not hook.is_file() or not os.access(hook, os.X_OK):
        raise NoteError(f"hook is missing or not executable: {hook}")
    hooks_paths = _config_values("core.hooksPath", root)
    accepted_paths = {".githooks", str((root / ".githooks").resolve())}
    if hooks_paths and hooks_paths[-1] not in accepted_paths:
        raise NoteError(f"core.hooksPath is already set to {hooks_paths[-1]!r}")
    configured_alias = _run(
        ["jj", "config", "list", "aliases.ci"], cwd=root
    ).stdout.strip()
    if configured_alias and "scripts/size_note.py" not in configured_alias:
        raise NoteError("the jj ci alias is already configured")
    _run(
        ["jj", "config", "set", "--repo", "aliases.ci", json.dumps(JJ_ALIAS)], cwd=root
    )
    _git(["config", "--local", "core.hooksPath", ".githooks"], root=root)
    if NOTES_REF not in _config_values("notes.displayRef", root):
        _git(["config", "--local", "--add", "notes.displayRef", NOTES_REF], root=root)
    print("size-note: installed Git post-commit hook and jj ci wrapper", file=sys.stderr)


def parse_note_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="manage exact-commit size measurements")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("install", help="configure this Git/jj repository")
    record_parser = commands.add_parser("record", help="measure and note one Git commit")
    record_parser.add_argument("revision", nargs="?", default="HEAD")
    record_parser.add_argument("--force", action="store_true", help="replace an existing measurement")
    record_parser.add_argument("--analyser", help="revision providing analyser scripts")
    backfill_parser = commands.add_parser("backfill", help="measure every commit in an ancestry range")
    backfill_parser.add_argument("base")
    backfill_parser.add_argument("tip", nargs="?", default="HEAD")
    backfill_parser.add_argument("--analyser", help="revision providing analyser scripts (default: tip)")
    backfill_parser.add_argument("--include-base", action="store_true", help="also measure the base revision")
    backfill_parser.add_argument("--record-errors", action="store_true", help="note unavailable analyses and continue")
    return parser.parse_args(argv)


def note_main(argv: list[str] | None = None, *, root: Path = ROOT) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    try:
        if arguments and arguments[0] == "jj-commit":
            return jj_commit(arguments[1:], root=root)
        args = parse_note_args(arguments)
        if args.command == "install":
            install(root=root)
        elif args.command == "backfill":
            backfill(
                args.base, args.tip, root=root, analyser_revision=args.analyser,
                include_base=args.include_base, record_errors=args.record_errors,
            )
        else:
            record(
                args.revision, root=root, analyser_revision=args.analyser, force=args.force
            )
    except NoteError as error:
        print(f"size-note: {error}", file=sys.stderr)
        return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    if not arguments or arguments[0] not in ("size", "perf", "size-note"):
        print("usage: pipeline.py {size,perf,size-note} [options]", file=sys.stderr)
        return 2
    if arguments[0] == "size":
        return size_main(arguments[1:])
    if arguments[0] == "perf":
        return perf_main(arguments[1:])
    return note_main(arguments[1:])


if __name__ == "__main__":
    raise SystemExit(main())
