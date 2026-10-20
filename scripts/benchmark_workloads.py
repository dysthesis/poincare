"""Workload definitions and deterministic, disposable on-disk projects.

This module deliberately has no Neovim, Nix, or MessagePack dependency.
"""

from __future__ import annotations

import hashlib
import os
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

CORPUS_VERSION = "poincare-synthetic-project/v1"
AUTHOR = "Poincare Benchmark"
COMMIT_DATE = "2026-01-01T12:00:00+0000"
PICKER_QUERY = "unique_target_173"
GREP_QUERY = "PIN_BENCH_NEEDLE_7E21"
LINT_TOKEN = "benchmark_unique_undefined_7e21"
COMPLETION_WORD = "benchmark_albatross"
LSP_COMPLETION_WORD = "benchmark_completion_target"


@dataclass(frozen=True)
class Workload:
    name: str
    suite: str
    description: str
    requirements: tuple[str, ...]
    latency_boundary: str
    application_state: str = (
        "fresh process; prepared interaction unless stated otherwise"
    )
    fixtures: tuple[str, ...] = ()
    action: str = ""
    readiness: str = ""
    limitations: tuple[str, ...] = (
        "deterministic synthetic corpus; no empirical user-workload frequencies",
        "remote-UI flush, not terminal/compositor/physical display latency",
    )

    def metadata(self) -> dict[str, Any]:
        value = asdict(self)
        value["requirements"] = list(self.requirements)
        for key in ("fixtures", "limitations"):
            value[key] = list(value[key])
        value["common_requirements"] = [
            "git for deterministic on-disk index/commit",
            "msgpack Python dependency for run only",
        ]
        return value


_INPUT_END = (
    "input dispatch to semantic oracle, then a subsequent remote-UI redraw flush"
)
_STARTUP_END = (
    "process spawn to VimEnter/configuration + checked viewport and subsequent remote-UI flush; "
    "includes UI attach, RPC handshake, minimal inline readiness observer and startup-only real <CR> "
    "acknowledgements of observed Hit-enter prompts; no human think time"
)
CATALOG = (
    Workload(
        "startup-empty",
        "core",
        "Start the configured empty editor with statusline, completion and pins.",
        ("configured statusline, mini.completion and pins",),
        _STARTUP_END,
        "fresh process; empty buffer; no full scenario harness loaded",
        action="spawn nvim --embed and attach fixed UI",
        readiness="VimEnter; configured statusline/completion/pins and mappings; rendered [No Name]",
    ),
    Workload(
        "startup-file",
        "core",
        "Start with a representative Lua file and default closed method folds; not LSP-ready.",
        ("Lua parser/highlighter", "configured Lua method folds"),
        _STARTUP_END,
        "fresh process; Lua file on argv; no full scenario harness loaded",
        fixtures=("lua/representative.lua",),
        action="spawn nvim --embed lua/representative.lua and attach fixed UI",
        readiness="VimEnter/configuration; path/filetype/count/sentinels; active highlighter; exact default closed fold; rendered filename",
    ),
    Workload(
        "open-python",
        "core",
        "Edit a heterogeneous ~300-line Python source; syntax only, no Python LSP.",
        ("Python parser/highlighter",),
        _INPUT_END,
        fixtures=("python/representative.py",),
        action=":edit python/representative.py<CR>",
        readiness="path/filetype/count/first+last lines; active highlighter; rendered filename",
    ),
    Workload(
        "open-rust",
        "core",
        "Edit a heterogeneous ~300-line Rust source with default method folds; no Cargo/indexing boundary.",
        ("Rust parser/highlighter", "configured Rust method folds"),
        _INPUT_END,
        fixtures=("rust/representative.rs",),
        action=":edit rust/representative.rs<CR>",
        readiness="path/filetype/count/sentinels; active highlighter; default closed method fold; rendered filename",
    ),
    Workload(
        "open-nix",
        "core",
        "Edit a ~300-line Nix expression; no evaluator or LSP readiness boundary.",
        ("Nix parser/highlighter",),
        _INPUT_END,
        fixtures=("nix/representative.nix",),
        action=":edit nix/representative.nix<CR>",
        readiness="path/filetype/count/sentinels; active highlighter; rendered filename",
    ),
    Workload(
        "open-large",
        "stress",
        "Edit a valid 12,004-line heterogeneous Python module; first highlighted viewport, not full-file parse.",
        ("Python parser/highlighter",),
        _INPUT_END,
        fixtures=("python/large.py",),
        action=":edit python/large.py<CR>",
        readiness="O(1) path/filetype/count/sentinels; active highlighter and rendered filename; no observer parser:parse()",
    ),
    Workload(
        "edit-insert",
        "core",
        "Type three paired delimiters and contents through mini.pairs; check exact text and normal mode.",
        ("mini.pairs insert mappings",),
        _INPUT_END,
        fixtures=("text/edit.txt",),
        action="A (alpha<Right>[beta<Right>{gamma<Esc>",
        readiness="exact seed (alpha)[beta]{gamma}; normal mode; active mini.pairs mapping",
    ),
    Workload(
        "edit-paste-undo",
        "core",
        "Paste 24 valid Lua functions (96 lines) with nvim_paste, check insertion, then undo and check whole-buffer restoration.",
        ("Lua parser/highlighter", "configured Lua method folds", "nvim_paste"),
        "before nvim_paste dispatch through checked paste + real undo keys, exact restoration and subsequent UI flush; one composite burst",
        fixtures=("lua/representative.lua",),
        action="nvim_paste(96-line Lua burst), check inserted text, <Esc>u",
        readiness="exact intermediate insertion and exact whole-buffer restoration; normal mode; active highlighter/folds",
    ),
    Workload(
        "treesitter-motion",
        "core",
        "Mapped ]m moves from the first Lua function to the exact second function start.",
        ("Lua parser/highlighter", "configured ]m textobject mapping"),
        _INPUT_END,
        fixtures=("lua/representative.lua",),
        action="]m",
        readiness="active highlighter; configured mapping; cursor exactly [12, 0]",
    ),
    Workload(
        "folds",
        "core",
        "Close prepared open Lua method folds using zM; check exact bounds and configured highlighted foldtext.",
        ("Lua parser/highlighter", "configured method foldexpr/foldtext"),
        _INPUT_END,
        fixtures=("lua/representative.lua",),
        action="zM",
        readiness="foldclosed(4)=4; foldclosedend(4)=10; configured highlighted foldtext contains … 7 lines …; rendered foldtext",
    ),
    Workload(
        "scroll",
        "core",
        "Three Ctrl-D then one Ctrl-U over Python syntax; fixed burst with exact cursor and topline.",
        ("Python parser/highlighter",),
        _INPUT_END + "; entire four-motion burst, not frame/FPS samples",
        fixtures=("python/representative.py",),
        action="<C-d><C-d><C-d><C-u>",
        readiness="cursor/topline equal 1+2*configured half-page size; cursor column 0",
    ),
    Workload(
        "buffer-switch",
        "core",
        "Ctrl-^ returns from a preopened Python buffer to a preopened Lua buffer with UI hooks enabled.",
        ("Lua/Python parsers", "configured statusline/gutter"),
        _INPUT_END,
        "fresh process; both buffers already opened",
        fixtures=("lua/representative.lua", "python/representative.py"),
        action="<C-^>",
        readiness="Lua path/filetype/count/sentinels/highlighter; statusline/gutter remain enabled",
    ),
    Workload(
        "split-resize",
        "core",
        "2<M-l> grows the left split by six columns, then <C-l> selects the right split.",
        (
            "configured Alt-h/j/k/l resize and Ctrl-h/j/k/l move mappings",
            "no inherited tmux",
        ),
        _INPUT_END,
        "fresh process; two prepared vertical splits",
        fixtures=("lua/representative.lua",),
        action="2<M-l><C-l>",
        readiness="left/right widths +6/-6; exact positions; right window selected; configured callbacks present",
    ),
    Workload(
        "completion-buffer",
        "core",
        "Type benchmark_al and await automatic mini.completion fallback with its configured debounce (current default 30ms).",
        (
            "mini.completion automatic completion (current default 30ms; actual delay recorded)",
        ),
        _INPUT_END + "; popup remains visible",
        fixtures=("text/completion.txt",),
        action="ibenchmark_al",
        readiness="visible popup includes benchmark_albatross; insert mode; mini.completion active and actual configured delay recorded; rendered candidate",
    ),
    Workload(
        "picker-files-first",
        "core",
        "Lazy-load the file picker via <leader>f, type a unique filename query, check full source and selected match.",
        (
            "mini.pick configured mapping",
            "backend: rg, then fd, then git, then filesystem fallback",
        ),
        _INPUT_END,
        "fresh process; mini.pick not previously loaded",
        fixtures=("whole tracked mixed-source project",),
        action="<leader>funique_target_173",
        readiness="full exact backend-appropriate file set; nonbusy source; exact query and unique current match; rendered menu",
    ),
    Workload(
        "picker-files-repeat",
        "core",
        "Repeat the same file query after fully loading and closing a first picker outside timing.",
        (
            "mini.pick configured mapping",
            "backend: rg, then fd, then git, then filesystem fallback",
        ),
        _INPUT_END,
        "fresh process; one complete picker open/close already performed",
        fixtures=("whole tracked mixed-source project",),
        action="<leader>funique_target_173",
        readiness="priming full-source open/close proven; repeated full file set/nonbusy source and unique current match",
    ),
    Workload(
        "picker-grep",
        "core",
        "<leader>/ runs a unique live query against the tracked corpus; exact filename/line and complete nonbusy result.",
        (
            "mini.pick configured mapping",
            "real rg or git executable (no grep fallback)",
        ),
        _INPUT_END,
        fixtures=("whole tracked mixed-source project", "text/grep-target.txt"),
        action="<leader>/PIN_BENCH_NEEDLE_7E21",
        readiness="exact completed query; nonbusy one-result source; text/grep-target.txt line 2; actual backend; rendered match",
    ),
    Workload(
        "git-gutter",
        "core",
        "Edit a tracked line after proving Git index attachment with a dirty/reset cycle; check GitGutterChange at that row.",
        ("git", "configured git-gutter renderer"),
        _INPUT_END,
        "fresh process; actual dirty/reset attachment cycle completed",
        fixtures=("text/gutter.txt", "fixed Git index"),
        action="A measured<Esc> on line 2",
        readiness="exact edited text and git-gutter namespace extmark GitGutterChange on zero-based row 1",
    ),
    Workload(
        "git-blame",
        "core",
        "Move to the next tracked line and await correct author, commit and row, including configured 150ms debounce.",
        ("git", "configured git_blame extmarks and GitBlame command"),
        _INPUT_END,
        "fresh process; first-line committed blame already visible",
        fixtures=("text/gutter.txt", "fixed Git commit"),
        action="j from line 1",
        readiness="git_blame virtual text on row 1 includes fixed author and commit; rendered annotation",
    ),
    Workload(
        "pins-select",
        "core",
        "Pin through <leader>h, move to Python untimed, then select the known Lua pin with <leader>1.",
        ("configured persistent pins mappings",),
        _INPUT_END,
        "fresh process; pin persisted/prepared; not cross-process session restore",
        fixtures=(
            "lua/representative.lua",
            "python/representative.py",
            "isolated persistent pin state",
        ),
        action="<leader>1",
        readiness="real unpin/pin normalization and persisted path checked untimed; correct Lua buffer/statusline/highlighter after selection",
    ),
    Workload(
        "format-save-lua",
        "tools",
        "Real :write formats deliberately unformatted Lua with stylua; exact buffer AND disk, modified flag clear.",
        ("stylua", "configured synchronous BufWritePre formatter"),
        _INPUT_END + "; formatter and disk write included",
        fixtures=("lua/format.lua", "stylua.toml"),
        action=":write<CR>",
        readiness="exact deterministic formatted buffer AND disk text; modified=false; actual stylua executable",
    ),
    Workload(
        "lint-lua",
        "tools",
        "Insert a unique undefined global then :write; await new Selene undefined_variable diagnostic, disk text and unmodified buffer.",
        ("selene", "configured nvim-lint selene source/namespace"),
        _INPUT_END + "; end-to-end edit/save-to-lint, including formatter if available",
        fixtures=("lua/lint.lua", "selene.toml", "stylua.toml"),
        action="Obenchmark_unique_undefined_7e21()<Esc>:write<CR> before line 2",
        readiness="new source=selene/code=undefined_variable diagnostic at exact line, actual namespace; exact disk+buffer and modified=false",
    ),
    Workload(
        "lsp-lua-ready",
        "tools",
        "Edit the real .luarc.json Lua project and await initialized attached configured Lua server and capabilities.",
        ("lua-language-server", "configured Lua LspAttach mappings/omnifunc"),
        _INPUT_END + "; attach-ready excludes full workspace indexing",
        fixtures=(".luarc.json", "lua/lsp_main.lua", "lua/benchlib.lua"),
        action=":edit lua/lsp_main.lua<CR>",
        readiness="initialized attached lua-language-server; definition+completion capabilities; configured buffer-local gd and omnifunc",
    ),
    Workload(
        "lsp-definition",
        "tools",
        "Use configured buffer-local gd on an imported symbol; exact cross-file Lua server definition destination.",
        (
            "lua-language-server",
            "initialized configured Lua client and buffer-local gd",
        ),
        _INPUT_END,
        "fresh process; initialized Lua server and source buffer prepared; remaining indexing may be included",
        fixtures=(".luarc.json", "lua/lsp_main.lua", "lua/benchlib.lua"),
        action="gd on library.benchmark_transform use",
        readiness="configured buffer-local gd; exact cross-file destination lua/benchlib.lua [2, 11]; attached initialized client",
    ),
    Workload(
        "completion-lsp",
        "tools",
        "After observed workspace indexing, explicit Ctrl-X Ctrl-O invokes configured omnifunc for an imported member absent from the current buffer.",
        (
            "lua-language-server with observed Loading workspace begin/end progress",
            "mini.completion configured omnifunc and LSP-provenance completion item",
        ),
        _INPUT_END
        + "; explicit omnifunc invocation in indexed workspace, not first completion during indexing or automatic debounce; popup remains visible",
        "fresh process; initialized Lua server and observed completed Loading workspace progress prepared untimed; no active loading tokens",
        fixtures=(".luarc.json", "lua/lsp_main.lua", "lua/benchlib.lua"),
        action="Olocal completed = library.benchmark_comp<C-x><C-o>",
        readiness="preparation: real Loading workspace begin/end per client+token and no active tokens; measured: visible complete_info mode=omni popup, benchmark_completion_target with real LSP client provenance, rendered candidate",
    ),
    Workload(
        "redraw-control",
        "calibration",
        "Diagnostic no-change oracle/redraw request on a prepared live UI; inclusive harness floor, NEVER subtracted.",
        ("attached remote UI",),
        "RPC request dispatch to immediately successful observer and subsequent redraw flush; diagnostic only",
        action="RPC immediately successful observer + redraw!",
        readiness="ordered oracle notification then subsequent nonempty remote-UI flush",
        limitations=(
            "diagnostic harness floor, not a user workload or subtractable constant",
            "no aggregate score or per-frame inference",
        ),
    ),
)
BY_NAME = {workload.name: workload for workload in CATALOG}
SUITES = ("core", "tools", "stress", "calibration", "all")


def select_workloads(
    suites: list[str] | None, names: list[str] | None
) -> list[Workload]:
    suites = suites or ([] if names else ["core"])
    names = names or []
    unknown = set(names) - BY_NAME.keys()
    if unknown:
        raise ValueError("unknown workload(s): " + ", ".join(sorted(unknown)))
    unknown_suites = set(suites) - set(SUITES)
    if unknown_suites:
        raise ValueError("unknown suite(s): " + ", ".join(sorted(unknown_suites)))
    return [
        workload
        for workload in CATALOG
        if workload.name in names or workload.suite in suites or "all" in suites
    ]


def _python_source(functions: int, title: str) -> str:
    lines = [
        f'"""{title}; deterministic synthetic syntax workload, not user code."""',
        "from math import sqrt",
        "",
        "",
    ]
    for index in range(functions):
        lines.extend(
            [
                f"def sample_{index:04d}(values, scale={index % 11 + 1}):",
                f'    """Transform partition {index} with a bounded heterogeneous expression."""',
                f"    adjusted = [value + {index % 19} for value in values if value >= 0]",
                "    if not adjusted:",
                '        return {"count": 0, "value": 0.0}',
                "    total = sum(adjusted) * scale",
                '    return {"count": len(adjusted), "value": sqrt(total + 1)}',
                "",
            ]
        )
    return "\n".join(lines) + "\n"


def corpus_files() -> dict[str, str]:
    lua = ["-- Poincare representative Lua syntax corpus", "local M = {}", ""]
    rust = ["// Poincare representative Rust syntax corpus", "#![allow(dead_code)]", ""]
    for index in range(36):
        lua.extend(
            [
                f"function M.sample_{index:03d}(value)",
                f"  local offset = value + {index}",
                "  if offset % 2 == 0 then",
                "    return offset * 2",
                "  end",
                "  return offset - 1",
                "end",
                "",
            ]
        )
        rust.extend(
            [
                f"fn sample_{index:03d}(value: i64) -> i64 {{",
                f"    let offset = value + {index};",
                "    if offset % 2 == 0 {",
                "        offset * 2",
                "    } else {",
                "        offset - 1",
                "    }",
                "}",
                "",
            ]
        )
    lua.append("return M")
    nix = ["# Poincare representative Nix syntax corpus", "{ seed ? 7 }:", "let"]
    for index in range(100):
        nix.extend(
            [
                f"  sample{index:03d} = let",
                f"    offset = seed + {index};",
                "  in if offset > 10 then offset * 2 else offset + 3;",
            ]
        )
    nix.extend(["in {", "  inherit sample000 sample049 sample099;", "}"])
    files = {
        "lua/representative.lua": "\n".join(lua) + "\n",
        "python/representative.py": _python_source(40, "Representative Python"),
        "python/large.py": _python_source(1500, "Large Python (12,004 lines)"),
        "rust/representative.rs": "\n".join(rust) + "\n",
        "nix/representative.nix": "\n".join(nix) + "\n",
        "text/edit.txt": "seed\n",
        "text/completion.txt": f"{COMPLETION_WORD} benchmark_alchemy benchmark_alluvial\n\n\n",
        "text/gutter.txt": "gutter baseline alpha\ngutter baseline beta\ngutter baseline gamma\n",
        "text/grep-target.txt": f"ordinary introductory line\n{GREP_QUERY}\nordinary concluding line\n",
        "lua/format.lua": "local value={answer=42}\nreturn value\n",
        "lua/lint.lua": "local value = 1\nlocal result = value + 2\nreturn result\n",
        "lua/benchlib.lua": "local M = {}\nfunction M.benchmark_transform(value)\n  return value * 3\nend\nfunction M.benchmark_completion_target(value)\n  return value + 7\nend\nreturn M\n",
        "lua/lsp_main.lua": 'local library = require("benchlib")\nlocal input = 14\nlocal output = library.benchmark_transform(input)\nreturn output\n',
        ".luarc.json": '{"workspace":{"checkThirdParty":false},"runtime":{"version":"LuaJIT","path":["lua/?.lua","lua/?/init.lua"]},"telemetry":{"enable":false}}\n',
        "stylua.toml": 'indent_type = "Spaces"\nindent_width = 2\ncolumn_width = 100\nquote_style = "AutoPreferDouble"\n',
        "selene.toml": 'std = "lua51"\n',
    }
    for index in range(256):
        name = f"unique_target_{index:03d}" if index == 173 else f"module_{index:03d}"
        files[f"candidates/group_{index % 8}/{name}.lua"] = (
            f"-- Synthetic candidate partition {index % 8}, item {index}\n"
            f'local item = {{ index = {index}, label = "sample-{index:03d}" }}\n'
            "return item\n"
        )
    return files


def corpus_metadata(files: dict[str, str]) -> dict[str, Any]:
    digest = hashlib.sha256()
    entries = []
    for name, text in sorted(files.items()):
        data = text.encode("utf-8")
        digest.update(name.encode() + b"\0" + len(data).to_bytes(8, "big") + data)
        entries.append(
            {
                "path": name,
                "bytes": len(data),
                "lines": len(text.splitlines()),
                "sha256": hashlib.sha256(data).hexdigest(),
            }
        )
    return {
        "schema": CORPUS_VERSION,
        "sha256": digest.hexdigest(),
        "file_count": len(entries),
        "bytes": sum(entry["bytes"] for entry in entries),
        "lines": sum(entry["lines"] for entry in entries),
        "candidate_files": 256,
        "files": entries,
        "git_author": AUTHOR,
        "git_commit_date": COMMIT_DATE,
        "scope": "deterministic synthetic mixed-source Git project; no empirical workload-frequency weighting",
    }


def corpus_file_facts(files: dict[str, str]) -> dict[str, dict[str, Any]]:
    """Materialize cheap observer inputs once, before any editor is spawned."""
    filetypes = {".lua": "lua", ".py": "python", ".rs": "rust", ".nix": "nix"}
    facts = {}
    for name, text in files.items():
        source_lines = text.splitlines()
        filetype = filetypes.get(Path(name).suffix)
        facts[name] = {
            "count": len(source_lines),
            "first": source_lines[0],
            "last": source_lines[-1],
            "filetype": filetype or "",
            "syntax": filetype is not None,
        }
    return facts


def restore_project(
    root: Path, files: dict[str, str], environment: dict[str, str]
) -> str:
    """Restore all source bytes, creating one fixed Git index/commit on first use."""
    root.mkdir(parents=True, exist_ok=True)
    for name, text in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text.encode("utf-8"))
    git_environment = environment | {
        "GIT_AUTHOR_NAME": AUTHOR,
        "GIT_AUTHOR_EMAIL": "benchmark@example.invalid",
        "GIT_COMMITTER_NAME": AUTHOR,
        "GIT_COMMITTER_EMAIL": "benchmark@example.invalid",
        "GIT_AUTHOR_DATE": COMMIT_DATE,
        "GIT_COMMITTER_DATE": COMMIT_DATE,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": os.devnull,
    }
    commands = (
        []
        if (root / ".git").is_dir()
        else [
            ["git", "-c", "init.defaultBranch=benchmark", "init", "--quiet"],
            ["git", "-c", "core.autocrlf=false", "add", "--all"],
            [
                "git",
                "-c",
                "commit.gpgsign=false",
                "-c",
                "core.hooksPath=/dev/null",
                "commit",
                "--quiet",
                "--no-gpg-sign",
                "-m",
                "Fixed synthetic benchmark corpus",
            ],
        ]
    )
    commands.append(["git", "rev-parse", "HEAD"])
    result = None
    for command in commands:
        result = subprocess.run(
            command,
            cwd=root,
            env=git_environment,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        if result.returncode:
            raise RuntimeError(
                f"fixture command {command!r} failed: {result.stderr.strip()}"
            )
    assert result is not None
    return result.stdout.strip()


def scenario_config(
    workload: Workload, files: dict[str, str], facts: dict[str, dict[str, Any]]
) -> dict[str, Any]:
    """Return only this case's observer data, never the whole source corpus."""
    name = workload.name
    config: dict[str, Any] = {
        "file_facts": {
            path: facts[path] for path in workload.fixtures if path in facts
        },
        "lua_first_function": 4,
        "lua_first_fold_end": 10,
        "lua_second_function": 12,
        "rust_first_fold_end": 11,
    }
    if name in ("picker-files-first", "picker-files-repeat"):
        config.update(
            {
                "all_names": sorted(files),
                "visible_names": sorted(
                    path for path in files if not path.startswith(".")
                ),
                "picker_query": PICKER_QUERY,
                "picker_target": "candidates/group_5/unique_target_173.lua",
            }
        )
    if name == "picker-grep":
        config.update(
            {
                "grep_query": GREP_QUERY,
                "grep_target": "text/grep-target.txt",
                "grep_line": 2,
            }
        )
    if name == "completion-buffer":
        config["completion_word"] = COMPLETION_WORD
    if name == "completion-lsp":
        config["lsp_completion_word"] = LSP_COMPLETION_WORD
    if name == "git-gutter":
        config["original_text"] = files["text/gutter.txt"]
    if name == "edit-paste-undo":
        original = files["lua/representative.lua"]
        paste = "".join(
            f"local function pasted_{index:03d}(value)\n  return value * {index + 2} + {index}\nend\n\n"
            for index in range(24)
        )
        config.update(
            {
                "original_text": original,
                "paste": paste,
                "pasted_text": paste + original,
                "original_sha256": hashlib.sha256(original.encode()).hexdigest(),
                "pasted_sha256": hashlib.sha256(
                    (paste + original).encode()
                ).hexdigest(),
            }
        )
    if name == "lint-lua":
        config["lint_token"] = LINT_TOKEN
    if name == "format-save-lua":
        config["format_expected"] = "local value = { answer = 42 }\nreturn value\n"
    if name == "lsp-definition":
        config.update(
            {
                "lsp_definition_row": 2,
                "lsp_definition_col": 11,
                "lsp_use_col": files["lua/lsp_main.lua"]
                .splitlines()[2]
                .index("benchmark_transform"),
            }
        )
    return config
