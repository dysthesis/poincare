from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import size_note


def git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *arguments],
        cwd=root,
        text=True,
        capture_output=True,
        check=True,
    )


class RecordTests(unittest.TestCase):
    def test_record_analyses_the_committed_tree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            git(root, "init", "--quiet")
            git(root, "config", "user.name", "Size Test")
            git(root, "config", "user.email", "size@example.invalid")
            scripts = root / "scripts"
            scripts.mkdir()
            (root / "flake.nix").write_text("{}\n")
            analyser = scripts / "size.py"
            measurement = {
                "format": size_note.MEASUREMENT_FORMAT,
                "runtime": {},
                "vm": {},
                "source_count": 1,
                "metrics": ["bytecodes"],
                "tree": {"name": "committed"},
            }
            analyser.write_text(
                "import json\nprint(json.dumps(" + repr(measurement) + "))\n"
            )
            (root / ".absolute-link").symlink_to("/nix/store/test-target")
            git(root, "add", "scripts/size.py", ".absolute-link", "flake.nix")
            git(root, "commit", "--quiet", "-m", "fixture")
            analyser.write_text("raise RuntimeError('working tree was analysed')\n")

            size_note.record("HEAD", root=root, change_id="test-change-id")

            note = json.loads(
                git(
                    root,
                    "notes",
                    f"--ref={size_note.NOTES_REF}",
                    "show",
                    "HEAD",
                ).stdout
            )
            self.assertEqual(note["format"], size_note.NOTE_FORMAT)
            self.assertEqual(note["analyser_commit"], note["commit"])
            self.assertIsNone(note["error"])
            self.assertEqual(note["jj_change_id"], "test-change-id")
            self.assertEqual(note["measurement"]["tree"]["name"], "committed")


@unittest.skipUnless(shutil.which("jj"), "jj is unavailable")
class InstallTests(unittest.TestCase):
    def test_jj_ci_records_the_created_commit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "config"
            repository = root / "repository"
            repository.mkdir()
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": str(config)}):
                git(repository, "init", "--quiet")
                git(repository, "config", "user.name", "Size Test")
                git(repository, "config", "user.email", "size@example.invalid")
                scripts = repository / "scripts"
                scripts.mkdir()
                shutil.copy(Path(size_note.__file__), scripts / "size_note.py")
                measurement = {
                    "format": size_note.MEASUREMENT_FORMAT,
                    "runtime": {},
                    "vm": {},
                    "source_count": 1,
                    "metrics": ["bytecodes"],
                    "tree": {"name": "through-jj"},
                }
                (scripts / "size.py").write_text(
                    "import json\nprint(json.dumps(" + repr(measurement) + "))\n"
                )
                (scripts / "bytecode.lua").write_text("-- fixture\n")
                hooks = repository / ".githooks"
                hooks.mkdir()
                hook = hooks / "post-commit"
                hook.write_text("#!/bin/sh\nexit 0\n")
                hook.chmod(0o755)
                tracked = repository / "tracked"
                tracked.write_text("before\n")
                git(repository, "add", ".")
                git(repository, "commit", "--quiet", "-m", "fixture")
                subprocess.run(
                    ["jj", "git", "init", "--colocate", "."],
                    cwd=repository,
                    text=True,
                    capture_output=True,
                    check=True,
                )
                subprocess.run(
                    ["jj", "config", "set", "--repo", "user.name", "Size Test"],
                    cwd=repository,
                    check=True,
                )
                subprocess.run(
                    [
                        "jj",
                        "config",
                        "set",
                        "--repo",
                        "user.email",
                        "size@example.invalid",
                    ],
                    cwd=repository,
                    check=True,
                )
                size_note.install(root=repository)
                (repository / "flake.nix").write_text("{}\n")
                tracked.write_text("after\n")

                subprocess.run(
                    ["jj", "ci", "-m", "measured"], cwd=repository, check=True
                )

                commit = subprocess.run(
                    [
                        "jj",
                        "log",
                        "--no-graph",
                        "-r",
                        "@-",
                        "-T",
                        "commit_id",
                    ],
                    cwd=repository,
                    text=True,
                    capture_output=True,
                    check=True,
                ).stdout.strip()
                note = json.loads(
                    git(
                        repository,
                        "notes",
                        f"--ref={size_note.NOTES_REF}",
                        "show",
                        commit,
                    ).stdout
                )
                self.assertEqual(note["commit"], commit)
                self.assertEqual(note["analyser_commit"], commit)
                self.assertIsNone(note["error"])
                self.assertEqual(note["measurement"]["tree"]["name"], "through-jj")
                self.assertTrue(note["jj_change_id"])

                initial = git(repository, "rev-parse", f"{commit}^").stdout.strip()
                size_note.backfill(
                    initial,
                    commit,
                    root=repository,
                    analyser_revision=commit,
                    include_base=True,
                    record_errors=True,
                )
                initial_note = json.loads(
                    git(
                        repository,
                        "notes",
                        f"--ref={size_note.NOTES_REF}",
                        "show",
                        initial,
                    ).stdout
                )
                self.assertEqual(initial_note["analyser_commit"], commit)
                self.assertIsNone(initial_note["measurement"])
                self.assertIn("has no flake.nix", initial_note["error"])


if __name__ == "__main__":
    unittest.main()
