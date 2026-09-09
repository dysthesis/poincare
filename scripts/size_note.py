#!/usr/bin/env python3
"""Attach exact-commit size measurements to refs/notes/poincare-size.

Jujutsu has no hook API. ``install`` therefore replaces its built-in ``ci``
alias with a wrapper around ``jj commit``; the full command remains unhooked.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
NOTES_REF = "refs/notes/poincare-size"
MEASUREMENT_FORMAT = "poincare-size/v1"
NOTE_FORMAT = "poincare-size-note/v2"
ANALYSER_PATHS = ["scripts/size.py", "scripts/bytecode.lua"]
JJ_ALIAS = [
    "util",
    "exec",
    "--",
    "sh",
    "-c",
    'exec python3 "$JJ_WORKSPACE_ROOT/scripts/size_note.py" jj-commit "$@"',
    "",
]


class NoteError(RuntimeError):
    pass


def _run(
    command: list[str],
    *,
    cwd: Path,
    check: bool = True,
    input: str | None = None,
) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            text=True,
            input=input,
            capture_output=True,
            check=False,
        )
    except OSError as error:
        raise NoteError(f"cannot run {command[0]}: {error}") from error
    if check and result.returncode:
        detail = result.stderr.strip() or result.stdout.strip()
        suffix = f": {detail}" if detail else ""
        raise NoteError(f"{' '.join(command)} failed{suffix}")
    return result


def _git(
    arguments: list[str],
    *,
    root: Path,
    check: bool = True,
    input: str | None = None,
) -> subprocess.CompletedProcess[str]:
    return _run(["git", *arguments], cwd=root, check=check, input=input)


def _resolve_commit(revision: str, root: Path) -> str:
    result = _git(
        ["rev-parse", "--verify", "--end-of-options", f"{revision}^{{commit}}"],
        root=root,
    )
    commit = result.stdout.strip()
    if not commit or any(character not in "0123456789abcdef" for character in commit):
        raise NoteError(f"git returned an invalid object ID for {revision!r}")
    return commit


def _has_note(commit: str, root: Path) -> bool:
    result = _git(
        ["notes", f"--ref={NOTES_REF}", "show", commit], root=root, check=False
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
            command,
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
    except OSError as error:
        raise NoteError(f"cannot run git archive: {error}") from error
    if result.returncode:
        detail = result.stderr.decode(errors="replace").strip()
        raise NoteError(f"git archive failed: {detail}")
    try:
        # The commit is executable input and contains an intentional absolute symlink.
        with tarfile.open(fileobj=io.BytesIO(result.stdout), mode="r:") as archive:
            archive.extractall(destination, filter="fully_trusted")
    except (OSError, tarfile.TarError) as error:
        raise NoteError(f"cannot extract commit {commit}: {error}") from error


def _analyse(commit: str, analyser: str, root: Path) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="poincare-size-") as temporary:
        source = Path(temporary)
        _extract(commit, source, root)
        if not (source / "flake.nix").is_file():
            raise NoteError(f"commit {commit} has no flake.nix")
        if analyser != commit:
            _extract(analyser, source, root, ANALYSER_PATHS)
        analyser_path = source / "scripts" / "size.py"
        if not analyser_path.is_file():
            raise NoteError(f"commit {commit} has no scripts/size.py")
        result = _run([sys.executable, str(analyser_path), "--json"], cwd=source)
        try:
            measurement = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise NoteError("size.py did not emit valid JSON") from error
    if (
        not isinstance(measurement, dict)
        or measurement.get("format") != MEASUREMENT_FORMAT
    ):
        raise NoteError(f"size.py did not emit {MEASUREMENT_FORMAT}")
    return measurement


def _attach_note(
    commit: str,
    analyser: str,
    change_id: str | None,
    measurement: dict[str, Any] | None,
    error: str | None,
    *,
    root: Path,
    force: bool = False,
) -> None:
    note = {
        "format": NOTE_FORMAT,
        "commit": commit,
        "jj_change_id": change_id,
        "analyser_commit": analyser,
        "measurement": measurement,
        "error": error,
    }
    payload = json.dumps(note, indent=2, sort_keys=True) + "\n"
    arguments = ["notes", f"--ref={NOTES_REF}", "add"]
    if force:
        arguments.append("--force")
    arguments.extend(["--file=-", commit])
    _git(arguments, root=root, input=payload)
    print(f"size-note: attached {NOTES_REF} to {commit[:12]}", file=sys.stderr)


def record(
    revision: str,
    *,
    root: Path = ROOT,
    change_id: str | None = None,
    analyser_revision: str | None = None,
    force: bool = False,
) -> None:
    commit = _resolve_commit(revision, root)
    if not force and _has_note(commit, root):
        print(f"size-note: {commit[:12]} already has a measurement", file=sys.stderr)
        return

    print(f"size-note: measuring {commit[:12]}", file=sys.stderr)
    analyser = _resolve_commit(analyser_revision or commit, root)
    _attach_note(
        commit,
        analyser,
        change_id,
        _analyse(commit, analyser, root),
        None,
        root=root,
        force=force,
    )


def _jj_change_id(commit: str, root: Path) -> str | None:
    result = _run(
        [
            "jj",
            "--ignore-working-copy",
            "log",
            "--no-graph",
            "-r",
            commit,
            "-T",
            'change_id ++ "\\n"',
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
) -> None:
    base = _resolve_commit(base_revision, root)
    tip = _resolve_commit(tip_revision, root)
    ancestry = _git(["merge-base", "--is-ancestor", base, tip], root=root, check=False)
    if ancestry.returncode == 1:
        raise NoteError(f"{base_revision!r} is not an ancestor of {tip_revision!r}")
    if ancestry.returncode:
        detail = ancestry.stderr.strip() or ancestry.stdout.strip()
        raise NoteError(f"cannot inspect the requested commit range: {detail}")
    result = _git(
        ["rev-list", "--reverse", "--topo-order", f"{base}..{tip}"], root=root
    )
    commits = result.stdout.splitlines()
    if include_base:
        commits.insert(0, base)
    analyser = _resolve_commit(analyser_revision or tip, root)
    print(
        f"size-note: backfilling {len(commits)} commits with analyser {analyser[:12]}",
        file=sys.stderr,
    )
    failures = 0
    for index, commit in enumerate(commits, 1):
        print(f"size-note: [{index}/{len(commits)}]", file=sys.stderr)
        change_id = _jj_change_id(commit, root)
        try:
            record(
                commit,
                root=root,
                change_id=change_id,
                analyser_revision=analyser,
            )
        except NoteError as error:
            if not record_errors:
                raise
            failures += 1
            print(f"size-note: unavailable: {error}", file=sys.stderr)
            _attach_note(
                commit,
                analyser,
                change_id,
                None,
                str(error),
                root=root,
            )
    if failures:
        print(
            f"size-note: recorded {failures} unavailable measurements",
            file=sys.stderr,
        )


def _jj_identity(root: Path) -> tuple[str, str]:
    result = _run(
        [
            "jj",
            "log",
            "--no-graph",
            "-r",
            "@-",
            "-T",
            'commit_id ++ "\\n" ++ change_id ++ "\\n"',
        ],
        cwd=root,
    )
    lines = result.stdout.splitlines()
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
    git_root = Path(
        _git(["rev-parse", "--show-toplevel"], root=root).stdout.strip()
    ).resolve()
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
        ["jj", "config", "set", "--repo", "aliases.ci", json.dumps(JJ_ALIAS)],
        cwd=root,
    )
    _git(["config", "--local", "core.hooksPath", ".githooks"], root=root)
    if NOTES_REF not in _config_values("notes.displayRef", root):
        _git(["config", "--local", "--add", "notes.displayRef", NOTES_REF], root=root)
    print(
        "size-note: installed Git post-commit hook and jj ci wrapper", file=sys.stderr
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("install", help="configure this Git/jj repository")
    record_parser = commands.add_parser(
        "record", help="measure and note one Git commit"
    )
    record_parser.add_argument("revision", nargs="?", default="HEAD")
    record_parser.add_argument(
        "--force", action="store_true", help="replace an existing measurement"
    )
    record_parser.add_argument(
        "--analyser", help="revision providing size.py and bytecode.lua"
    )
    backfill_parser = commands.add_parser(
        "backfill", help="measure every commit in an ancestry range"
    )
    backfill_parser.add_argument("base")
    backfill_parser.add_argument("tip", nargs="?", default="HEAD")
    backfill_parser.add_argument(
        "--analyser", help="revision providing size.py and bytecode.lua (default: tip)"
    )
    backfill_parser.add_argument(
        "--include-base", action="store_true", help="also measure the base revision"
    )
    backfill_parser.add_argument(
        "--record-errors",
        action="store_true",
        help="attach unavailable notes and continue when analysis fails",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    try:
        if arguments and arguments[0] == "jj-commit":
            return jj_commit(arguments[1:])
        args = parse_args(arguments)
        if args.command == "install":
            install()
        elif args.command == "backfill":
            backfill(
                args.base,
                args.tip,
                analyser_revision=args.analyser,
                include_base=args.include_base,
                record_errors=args.record_errors,
            )
        else:
            record(
                args.revision,
                analyser_revision=args.analyser,
                force=args.force,
            )
    except NoteError as error:
        print(f"size-note: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
