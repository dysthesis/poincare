# Workload-first Neovim benchmarks

`benchmark.py` measures the packaged configuration performing checked editor
workloads through a real attached Neovim remote UI. Its interaction endpoint is
**input-to-checked-forced-redraw**, not uninstrumented keystroke/render latency:
the observer explicitly requests `redraw!` after semantic success. It is not a
collection of `--headless +qa` startup times, a plugin import profiler, or an
estimate of a particular person's daily workload mix. There is no weighted
aggregate score. Each named workload is a separate endpoint.

`perf.py` and the existing `scripts/benches/` JSON workloads remain **diagnostic
headless profiling and component attribution** tools. Their profile/history
formats, APIs, and behavior are unchanged. Use `just profile ...` for those
questions. Do not compare their instrumented timings with this benchmark's UI
latencies or treat a historical profiler run as a paired baseline.

## Commands and dependencies

From the repository root:

```sh
just bench list
just bench run --output candidate.jsonl
just bench report candidate.jsonl
just bench report candidate.jsonl --details
just bench report candidate.jsonl --plain
just bench report candidate.jsonl --json
just benchmark-test
```

`just bench *ARGS` runs `nix develop -c python3 scripts/benchmark.py`, so the
flake's Python dependencies and development tools are available even outside
the development shell or inside a stale shell. Nix environment setup happens
before collection and is not timed. The subcommand is explicit.

Direct `python3 scripts/benchmark.py list` and `report` invocations work with
the Python standard library alone. Rich is imported lazily for supported
interactive terminals; redirected output and missing Rich use a concise
standard-library report. Actual collection also requires the maintained Python
`msgpack` package, provided alongside `rich` in the development shell. MessagePack
is imported lazily, not while loading the catalog or analyzing an existing journal.

Without `--nvim`, collection realizes the current packaged `.#poincare` and
`.#poincare.packpath` through the shared Nix pipeline before timing anything.
It does not silently trust the potentially stale `result/` symlink. `--nvim`
selects an already built configured wrapper, not a bare editor with an unrelated
configuration. `--baseline` adds a second existing configured wrapper to **the
same invocation**, producing adjacent randomized baseline/candidate pairs.
For example, with two previously saved package outputs at these paths:

```sh
just bench run --baseline ./baseline/bin/nvim --nvim ./candidate/bin/nvim \
  --workload startup-file --workload edit-insert \
  --repeat 60 --warmups 3 --resamples 100000 --confidence 0.95 \
  --practical 0.05 --seed 20261020 --output comparison.jsonl
just bench report comparison.jsonl --json
```

The option-free `report` replays the stored analysis plan. For a deliberately
different sensitivity analysis, an explicit flag is retained and labeled as an
override, even when its value equals the stored value:

```sh
just bench report comparison.jsonl --block-length 6 --json
```

The baseline is not built from a Git revision by this command. Preserve real
package outputs and their external tools deliberately. An old JSONL file can be
replayed, but there is no unpaired historical significance test.

Workload selection is a union of repeatable `--suite` and `--workload` options.
With neither option, `run` selects `core`, while `list` shows `all` with corpus
sizes/hash. With only `--workload`, precisely those names are selected; `core`
is not implicitly added. Available suites are `core`, `tools`, `stress`,
`calibration`, and `all`. `list --json` exposes catalog/fixture metadata, not a
claim that required tools are installed. Examples:

```sh
just bench list --suite tools
just bench run --workload picker-files-first --workload picker-files-repeat \
  --output picker.jsonl
just bench run --suite tools --state fresh --output tools-fresh.jsonl
just bench run --suite stress --output large-file.jsonl
just bench run --suite calibration --output redraw-floor.jsonl
```

The package bundles the configuration/plugins, **not** every language tool.
The disposable corpus uses real Git, so Git must be available even when the
selected endpoint is not a Git feature. The Lua tools cases need the actual
`stylua`, `selene`, or `lua-language-server` as listed below. File picking uses
the configuration/plugin's available backend; grep needs real `rg` or Git.
PATH and selected runtime tools are evidence, not interchangeable hidden
implementation details. Missing required executables, parsers, mappings, or
postconditions must produce a failure, never a mock result or a successful
"not applicable" sample. Choose the same external-tool environment for both
targets unless tool changes are intentionally part of the comparison.

The development shell supplies `pynvim-python` through its Python environment.
Neovim can select that working provider directly when the Python ftplugin
checks `has('python3')`, rather than synchronously probing multiple interpreters
without `pynvim`. This preserves Python-provider functionality; it does not
disable provider discovery globally or add Python to the standalone editor's
package closure. Provider-environment comparisons must retain separate old/new
tool environments rather than give both targets the newly configured PATH.

Language setup checks configured formatter/server fallbacks for multiple
languages at startup, not only the selected fixture's filetype. Missing an
optional language tool can therefore emit a real warning even during
`startup-empty`. Such warnings are environment evidence, not an instruction to
disable production configuration; a tool required by the selected workload
still must be present and its readiness oracle must pass.

`run --output PATH` is required and refuses to overwrite an existing journal.
Each record is flushed and fsynced as collected. `--json` is available on both
`run` and `report`; it changes report presentation, not the JSONL evidence.
Relevant collection controls are:

- `--timeout 30`: measured startup/operation deadline in seconds.
- `--prepare-timeout 60`: per untimed startup/preparation-oracle deadline.
- `--width 120 --height 40`: remote UI dimensions; this checked corpus requires
  at least 60 columns and 20 rows.
- `--cpu-affinity 2,3`: explicitly choose CPUs from the current available affinity
  set on platforms supporting affinity. The harness records the choice and
  restores its original affinity on normal cleanup.
- `--keep-workdir`: retain disposable fixtures/state even after success.
  Failed or interrupted runs already retain their workspace and print its path
  to stderr; successful runs otherwise remove it.

Exit status is 0 for complete failure-free acquisition/replay and 1 for a
completed journal containing recorded workload errors/timeouts. A required
workload executable missing **during an observation**—for example, unavailable
`selene` in `lint-lua`—is a recorded error and a completed-run exit 1, not a
successful skipped case. Status 2 covers invalid CLI input/evidence and
collection prerequisites that fail **before journal acquisition**, such as
missing Python `msgpack`, an unavailable/nonexecutable Neovim target, or package
realization failure. Interruption exits 130 and leaves incomplete evidence.
**Status 0 is not a claim of sufficient sample size, adequate tail resolution,
or no regression.** Inspect decisions and warnings, not just the exit code.

## Reading reports and progress

The default report puts results first, rather than the acquisition metadata or
the complete analysis plan. It is the same compact summary in a terminal, a pipe,
or `--plain` output. Tables are capped at 120 columns; narrower terminals use
stacked workload cards without omitting names, interval endpoints, or verdicts.
Latency units are explicit and shared across the overview.

- **With a baseline:** each workload shows both medians, the measured paired
  percent change and its multiplicity-adjusted interval, and a verdict.
  Negative change means faster. The effect is the geometric mean of paired
  candidate/baseline ratios, **not** the ratio of the two displayed medians.
  `Slower`, `Faster`, `Within ±p%`, `Uncertain`, `Not enough evidence`, and
  `Failed` translate the existing statistical decisions; an uncertain result is
  not a finding of unchanged performance.
- **One target:** each workload shows its median and adjusted interval, p95,
  and successful/planned measured runs. A marker identifies weak p95 support.
  There is no implied baseline or speed verdict.
- **Failures and risks:** errors in warmups also make a workload `Failed`, even
  when every measured run succeeds. Default failed-workload timings are
  unavailable, not zero or survivor-only estimates. A bounded list of scoped
  reasons follows the results, with the total failure count and a pointer to
  full errors. Shared sample/bootstrap warnings are consolidated and distinguish
  collecting more measured runs from requesting more bootstrap resamples or
  choosing a shorter block. Sensitivity overrides remain visible.

Presentation flags do not change the experiment or journal schema:

- `run` and `report` **`--details`** replace the overview with the full statistical
  report: phase/status counts, descriptives, intervals, serial/drift diagnostics,
  paired absolute effects, analysis parameters, warnings, full errors and
  available exception traces. This is an alternative view, not a duplicate
  overview followed by the same data again.
- `run` and `report` **`--plain`** disable Rich presentation. Reports remain
  concise by default; combine with `--details` for the extended plain view.
- `run` **`--no-progress`** silences progress on stderr, without hiding the final
  report, failures in that report, or retained-workspace diagnostics.
- `run` and `report` **`--json`** keep stdout machine-readable and preserve the
  full analyzed evidence. Progress, when enabled, goes only to stderr.
  Raw host/affinity/hash/RNG metadata are not part of the default human report.

Collection progress covers dependency loading, package resolution/building,
fixture preparation, warmups, measurement, and analysis. Supported terminals use
a compact Rich display; redirected output, `--plain`, limited terminals
(`TERM=dumb`/`unknown`), and absent Rich use bounded stage/phase/coarse-milestone
logs plus every failure. `NO_COLOR` disables color without removing textual
meaning. Evidence strings are literal: Rich markup is not interpreted, and
terminal/control/bidirectional formatting characters are escaped in human output.

Progress refresh is **manual**, with no background worker, timer, or spinner.
Rich Live uses `auto_refresh=False` and does not redirect stdout or stderr.
Callbacks and terminal writes occur only at untimed boundaries, never from RPC
or readiness polling and never between a scoring timer's start and qualifying
redraw flush. During measurement the last status stays paused. Saved-attempt
counts include warmups and failures and advance only after the observation's
journal flush and fsync return. Remaining time is explicitly approximate during
collection; unknown-duration builds and analysis do not get invented estimates.
The display stops before the final report or retention diagnostics, and prints
the journal path once on completion or interruption. Progress policy/version
and harness identity are retained with the acquisition metadata. Terminal work
outside scored intervals can still affect host state: this is not a claim of
zero observer effect.

## Implemented workload matrix

The authoritative machine-readable catalog is `benchmark_workloads.py`, exposed
by `list`. Default UI dimensions are 120 columns by 40 rows. Except for startup,
preparation is outside the measured interval. Every successful action is checked
against its semantic oracle and a later redraw flush; merely loading a module,
emitting an autocmd, attaching a namespace, or opening a picker window is not
success.

### Core: 19 separate endpoints

| Name | Action, preparation, and checked completion |
| --- | --- |
| `startup-empty` | Spawn an empty editor; require VimEnter, configured statusline, completion/pins presence and mappings, and checked rendered viewport. Includes UI attach/RPC handshake, the minimal inline readiness observer, and startup-only real `<CR>` acknowledgement of observed Hit-enter prompts (no human think time). |
| `startup-file` | Spawn with the representative Lua file on argv; require expected path/line count/first and last lines/filetype, active highlighter, configured initially closed method fold, and UI readiness. **Not LSP-ready** or full workspace indexing. The full interaction harness is excluded from both startup timing intervals; it is loaded afterward for runtime evidence. |
| `open-python` | From an empty running editor, `:edit` the heterogeneous approximately 300-line Python fixture; check expected path/line count/first and last lines/filetype and highlighter. Syntax editing only; the configuration declares no Python LSP. |
| `open-rust` | `:edit` the representative Rust fixture; check expected path/line count/first and last lines/filetype/highlighter and configured default method folding. No Cargo dependency fetch or rust-analyzer readiness boundary. |
| `open-nix` | `:edit` the representative Nix expression; check expected path/line count/first and last lines/filetype/highlighter, not evaluation or server initialization. |
| `edit-insert` | Real insert keys enter three paired delimiters with contents through mini.pairs; require exact `seed (alpha)[beta]{gamma}` text and final normal mode. One fixed burst, not independent keystrokes. |
| `edit-paste-undo` | On prepared tracked Lua syntax, `nvim_paste` inserts 24 valid Lua functions (96 lines); check the exact inserted buffer, then issue actual undo keys and require exact whole-buffer restoration, normal mode, active highlighter and configured foldexpr. The entire paste/check/undo burst is **one** timed composite endpoint, including its intermediate oracle check. |
| `treesitter-motion` | On prepared unfolded Lua source, invoke the configured `]m` mapping and require the exact second function start/cursor and active highlighter. No private plugin handler calls. |
| `folds` | From prepared open Lua method folds, issue `zM`; require exact fold bounds and configured highlighted foldtext, including the expected seven-line folded region. |
| `scroll` | Three Ctrl-D followed by one Ctrl-U on prepared Python source; require exact cursor/topline. The four-motion burst has one latency, not four independent samples or an FPS estimate. |
| `buffer-switch` | Preopen Lua and Python files, then Ctrl-^ back to the known Lua buffer; check file readiness with configured statusline/gutter still enabled. |
| `split-resize` | Prepare two vertical windows; configured `2<M-l>` enlarges the left window by six columns and `<C-l>` selects the right. Require exact dimensions, positions, active window and real mappings; no inherited tmux. |
| `completion-buffer` | Type `benchmark_al` in the text fixture; wait for mini.completion's actual configured automatic completion/fallback to show a popup containing `benchmark_albatross`. The current source default is 30 ms; the target's actual delay is recorded, not required to equal 30 ms. The popup remains visible at the boundary. |
| `picker-files-first` | From mini.pick not yet loaded, invoke `<leader>f` and type the unique filename query. Require full known candidate source, nonbusy picker, and exactly the expected selected match, not just a picker window. |
| `picker-files-repeat` | Fully open and close the first picker untimed, then repeat the same checked file query. This separates lazy first use from a primed interaction **within a fresh process**. |
| `picker-grep` | Invoke `<leader>/` with a unique deterministic live query; require the real backend's complete nonbusy result for the exact tracked filename and line. Uses actual `rg` or Git, not mocked grep. |
| `git-gutter` | Prove baseline Git-index attachment through an actual dirty/reset cycle untimed; then edit the known tracked line and require its `GitGutterChange` mark at the exact row plus expected buffer text. Namespace existence alone is insufficient. |
| `git-blame` | Prepare visible committed blame for the first tracked line, move to the next line, and await correct author/commit/row. Includes the configured 150 ms debounce, rather than timing only an immediate helper call. |
| `pins-select` | Pin the known Lua file with `<leader>h`, move to Python untimed, then select with `<leader>1`; require the pinned file and UI. Exercises persisted pin state but does **not** claim cross-process session restoration. |

### Explicit external tools: five endpoints

| Name | Required real tool | Timed action and completion |
| --- | --- | --- |
| `format-save-lua` | `stylua` | `:write` on deliberately unformatted Lua through the configured synchronous formatter; require exact transformed buffer **and on-disk text**, and cleared modified flag. Formatter execution and writing are included. |
| `lint-lua` | `selene` | Real edit/save introduces a unique undefined global; require the new Selene `undefined_variable` diagnostic at the known row, its real source/namespace/code, exact disk/buffer text, and cleared modified flag. Initial stale work is settled untimed. This is end-to-end edit/save-to-lint, **not pure linter CPU time**; a configured formatter can also run when available. |
| `lsp-lua-ready` | `lua-language-server` | `:edit` a real Lua project with `.luarc.json`; require the configured initialized attached client, meaningful definition/completion capabilities, buffer-local `gd`, and configured omnifunc. Attach-ready excludes full workspace indexing. |
| `lsp-definition` | `lua-language-server` | Initialize the real server untimed, invoke configured buffer-local `gd` on an imported symbol, and require its exact **cross-file** destination/cursor and initialized client. Preparation requires attachment, not a completed-workspace-index barrier; remaining indexing or demand work may enter this operation's interval. |
| `completion-lsp-indexed` | `lua-language-server` with a checked cross-file definition response | Initialize the configured Lua server and resolve the fixture's imported definition **untimed**. Then send `Olocal completed = library.benchmark_comp<C-x><C-o>` once through real input and the configured omnifunc. Require the known label with real LSP provenance in the visible popup. The item is absent from the current buffer. This measures explicit completion after a checked definition barrier, not first completion during indexing, buffer fallback, or automatic debounce. |

An initialized/attached client advertising completion capabilities is not proof
that its workspace is indexed or that an imported-symbol completion will already
produce items. Attach latency, indexing readiness, and checked completion-menu
latency are distinct boundaries; an empty response must not be reclassified as
successful completion merely because attachment passed.

For `completion-lsp-indexed`, preparation sends one real
`textDocument/definition` request per initialized configured Lua client and
requires the exact `lua/benchlib.lua` destination at zero-based `[1,11]`.
LuaLS 3.19.1 gates definitions on `workspace.awaitReady`, so this establishes
workspace readiness without depending on its optional delayed progress UI.
Fast projects can finish loading without ever emitting `Loading workspace`.

Preparation evidence and `prepared_facts.workspace_barrier` retain the method,
expected destination, per-client request ID, result and completion timestamp.
Errors, rejected requests and wrong/empty destinations fail; an unanswered
request expires under the existing preparation deadline. No fixed sleep,
timed retry, synthetic event, or fallback to attachment alone is used.
Finalization checks the same client barriers again before measured input.

The definition request also warms resolution of the imported module. This is
a deliberately distinct contract from historical `completion-lsp`, which used
progress messages; do not compare those endpoint latencies as equivalent.
The new name identifies the cutover, while old journals remain replayable.
This LuaLS-specific barrier does not claim that all background work is idle.
`lsp-lua-ready` remains attach-only and `lsp-definition` still includes any
remaining initial indexing; neither is prewarmed by this completion barrier.

### Explicit stress and diagnostic calibration

- `open-large` (`stress`): edit a valid generated **12,004-line Python module**
  with heterogeneous function bodies. Completion is the checked file-ready
  viewport with an active highlighter, **not rendered syntax readiness**:
  asynchronous parsing can finish after this endpoint. This retains the
  original scoring boundary; older descriptions overstated it as highlighted.
- `open-large-highlighted` (`stress`): a distinct endpoint on the same file,
  from input through file readiness and a subsequent UI flush containing the
  exact docstring and `return` tokens in their configured syntax foregrounds.
  The surface marker is visible fixture content `sample_0000`, not a statusline
  filename that can truncate at supported viewport widths.
  The observer resolves token screen positions and highlight colors without
  forcing a parse. The remote-UI client rejects plain or incorrectly colored
  flushes and waits for the parser's natural later redraw under the original
  operation deadline. A missing/indistinguishable syntax foreground fails
  explicitly. Saved RGB highlight definitions and token requirements make the
  checked surface inspectable. Do not compare this endpoint with historical
  `open-large` latencies: its distinct name identifies the stronger contract.
  Actual bytes/lines/hashes are recorded for both cases; neither models
  arbitrary enormous proprietary projects or a physical display.
- `redraw-control` (`calibration`): on a prepared live UI, dispatch an immediately
  successful no-change observer, explicitly execute `redraw!`, and await the
  subsequent remote-UI flush. This measures the inclusive
  RPC/oracle/**forced-full-redraw** floor for that prepared state, **not a user
  workload**, and is not in default `core`. Never subtract it from another
  observation. The control cannot establish equal instrumentation overhead
  across workloads, screen states, or configurations, or isolate natural action
  latency by cancellation. Very short actions may be dominated by observer and
  forced-redraw work; their comparative ratios include those costs.

`all` includes calibration as well as core/tools/stress. For a clear experiment,
select only the endpoints you actually intend to interpret; selecting additional
endpoints changes the multiplicity family even if some later fail.

## Measurement, fixtures, and state

Each scheduled observation launches a **fresh Neovim process and child process
group**, using `--embed` rather than `--headless`. The client attaches a real RGB
`ext_linegrid` UI. User-level input, configured mappings/commands, and real
`nvim_paste` drive actions. Shutdown and process-group cleanup are outside the
scored interval; a language server is not reused as a warm persistent daemon
between process observations.

Interaction timing uses Python `perf_counter_ns` immediately before dispatch,
through receipt of a redraw flush **after** a workload-specific successful oracle
notification. On success, the Lua observer sends that notification and explicitly
executes **`vim.cmd('redraw!')`**, requesting a full redraw. The endpoint is
therefore **input-to-checked-forced-redraw**, not simply the timestamp of a
naturally occurring final action flush. Natural action redraws can occur earlier;
they cannot satisfy the post-oracle boundary.

`open-large-highlighted` additionally requires the specified syntax colors in
that post-oracle flush; the forced redraw can still be plain while parsing is
in progress, so a later natural redraw may be the first qualifying flush.

The Lua observer checks immediately, then defers at an explicitly recorded
**1 ms cadence** while waiting. Transport, RPC serialization, semantic checks,
polling, plugin delays, and the additional observation-driven full-redraw work
remain included. That work can dominate short interactions and amplify renderer
changes, so these numbers must not be presented as uninstrumented keystroke,
natural render, or physical display latency. No noisy overhead constant is
subtracted, and the calibration control cannot guarantee the same overhead for
each endpoint or target configuration.

Startup similarly begins at spawn and includes UI attach/handshake, readiness
observer installation, configuration/readiness checks, its explicit
`vim.cmd('redraw!')`, and the qualifying later flush. Its inline observer is
intentionally smaller than the full untimed interaction harness, but its
observation-driven forced redraw is still part of the startup boundary.

Neovim's [UI startup contract](https://neovim.io/doc/user/api-ui-events/#ui-startup)
explicitly warns that configuration loading can enter blocking prompts once the
UI attaches. Startup therefore cannot be defined as merely receiving the first
RPC response or a redraw while the editor is still waiting for acknowledgement.

During startup only, the RPC client checks the actual fast `nvim_get_mode()`
result at a 1 ms cadence. In documented Hit-enter mode `r`, it sends real
`nvim_input("<CR>")` and checks acceptance; it does not send blind Enter keys
in normal, More, confirmation, command-line, or arbitrary blocking states.
This handling stops at the startup completion notification, including for
interaction workloads whose initial startup is untimed. There is no later
automatic prompt acknowledgement and no separate opt-in prompt mode.

Both startup endpoints include the automatic acknowledgement/detection cost
when present, but **exclude human reading/think time**. Configuration warnings
remain enabled and are retained; no production notification options or plugins
are changed to avoid them. Each observation's `startup_prompts` records `policy`,
`count`, `acknowledgements`, `last_mode`, and `handling_stopped_at_perf_ns`.
Acknowledgements retain the observed mode, rendered prompt lines, detection and
dispatch timestamps, and accepted-input evidence. Runtime messages/stderr remain
additional evidence. A nonempty startup `vim.v.errmsg` is an error, not an
acknowledged success; required workload tools and semantic postconditions still
must pass. A timeout or failed startup still invalidates the affected workload
under the same no-survivor inference policy.

A flush is the remote UI protocol boundary, **not terminal-emulator painting,
compositor presentation, physical display latency, keyboard hardware latency,
or GPU frame time**. Final grid text/highlight IDs, checked oracle values, runtime
facts and stderr are retained as acquisition evidence. Extra evidence capture
outside the scored boundary must not be interpreted as additional latency
samples.

Fixtures are disposable real filesystem projects generated deterministically by
`benchmark_workloads.py`, schema `poincare-synthetic-project/v1`. The corpus has
mixed Lua/Python/Rust/Nix/text sources, bounded heterogeneous function bodies,
256 additional file-picker candidates, unique grep/completion/lint tokens, a
real fixed Git index/commit with fixed author/date, and local formatter/linter/LSP
configuration. It does not download Rust dependencies or require a database.
The manifest records corpus hash, aggregate counts, and each source file's bytes,
lines, and hash. Fixture creation, Git initialization, and restoration of original
source content occur outside the measured interval. Candidate-file count is not
a claim that every picker backend lists the same hidden files: the oracle checks
the appropriate complete known source and records the selected backend.

State policy is explicit:

- `--state warm` (default): isolated HOME/XDG directories are reused for that
  target/workload across the requested full-workload warmups and measured
  **fresh processes**. "Warm" names this directory-reuse/warmup policy, not a
  guarantee that every cache is populated, persisted, or equally useful to both
  wrappers. It is not a warm editor process.
- `--state fresh`: each observation gets new isolated HOME/XDG state. Fixtures
  are still deterministic, and the same workload-specific untimed preparation
  applies. "Fresh" does not undo preparation required by a primed workload.
- Neither policy drops the operating system page cache. Filesystem cache is
  uncontrolled/warmed and results are **not disk-cold**. No machine-wide cache,
  governor, scheduling, or user-project changes are made.
- Inherited Neovim/Lua init, tmux, Git override/user configuration, and desktop
  clipboard/session variables are isolated/stripped; XDG system directories are
  isolated too. The target wrapper's selected `NVIM_APPNAME` is preserved.
- ShaDa is disabled with `-i NONE` and swap files with `-n`; this is not a
  session-history restore workload. Directories used by configured persistent
  undo follow the isolated-state policy, but their population is not guaranteed.
  Process-group cleanup uses SIGTERM then bounded SIGKILL, not a graceful editor
  exit contract; caches requiring normal-exit writes may never be flushed.
- Optional explicit CPU affinity is a recorded experimental choice, not an
  automatic speed optimization. Run on a reasonably idle host and record power,
  background activity, thermal and virtualization conditions externally when
  they matter; the harness cannot establish that they were controlled.

Provenance includes target wrapper path/identity/hash/version, source lockfile
context, collector/statistics implementation and fixture identities, host/interpreter/clock/affinity facts,
state/environment/PATH policy, actual commands and tool availability, dimensions,
timeouts, seed, and the complete persisted schedule. A wrapper or `flake.lock`
hash is **not** a substitute for the recorded live runtime/plugin/tool facts.
Other available language tools can trigger normal configuration activity even
when an endpoint does not await their readiness. Keep that environment stable,
and inspect runtime facts before attributing differences to one plugin.

The collection-time statistics source identity is
`manifest.metadata.harness["benchmark_stats.py"]`; CLI replay also records the
current module's `analysis_source_identity`. An identical seed is not an exact
reproduction guarantee after the implementation changes: inspect both identities.

## Data-oriented implementation

The pipeline is organized around concrete data and transformations, rather than
one stateful benchmark object per feature:

1. **Catalog:** frozen workload descriptors expose fixtures, user action, semantic
   readiness, tool requirements, state, latency boundary and limitations as plain
   metadata. They describe real scenario code; there is no new execution DSL or
   generic feature/class hierarchy.
2. **Schedule:** plain phase/block/workload/target rows describe the fixed
   experiment before any process starts. Collection consumes this data without
   adaptive retries or changing the family.
3. **Journal:** append-only observation records preserve operational evidence
   (including UI grids and failures) independently of the statistical report.
4. **Analysis:** after one full schema/schedule validation per `analyze` call, a
   single pass transposes observations into per-workload/target chronological
   latency columns, integer measured block IDs, and phase/status counts. Failed
   measurements retain their block positions with null latency internally; they
   are never compacted into an inferential survivor series. Public records remain
   ordinary mutable dictionaries/lists, so no stale "already validated" cache is
   trusted after a caller edits them.
5. **Numeric kernels:** bootstrap loops receive only numeric lists and drawn
   integer indices. Paired log-ratios/differences are computed once; the same
   resampled index sequence feeds both effects and target medians. Metadata,
   error strings, screens and repeated dictionary filtering are outside these
   loops. Plain standard-library lists suffice; NumPy is not required.
6. **Presentation:** numeric results/counts/diagnostics are checked for finite
   output separately from already validated acquisition evidence; JSON and text
   rendering do not drive measurement or resampling. Rich failure evidence stays
   available without being copied into each resample.

## Experimental design and statistical interpretation

### Fixed processes, randomized adjacent pairs

Default collection uses **30 measured processes plus three warmups per
workload/target**. Warmups execute the same real workload and remain in the
journal but never enter scored descriptives, intervals, or temporal diagnostics.
There are no automatic retries, outlier deletions, replacement samples, or
adaptive extra rounds. Scheduling/GC/OS tails are part of the observed data.

The whole schedule is persisted before execution. Workload order is shuffled
within each round. For each workload in each phase, baseline/candidate order is
balanced and randomized: at 30 measured pairs there are 15 AB and 15 BA; for an
odd count the difference is at most one. The two target observations remain
adjacent. The round/block is the pairing unit, not arrival order after filtering
successful processes. This reduces exposure to slowly varying nuisance time and
environment conditions; it cannot make the host stationary or eliminate all
carryover effects.

Project and HOME/XDG paths are fixed **per target/workload**, not shared between
targets. A path- or state-dependent external service can therefore be confounded
with the target label despite adjacent AB/BA ordering. The 2026-10-24 investigation
in `OPTIMISATION.md` observed an indexed-completion slow mode that followed the
original project/state path pair when the two editor binaries were crossed over.
A surprising signal needs causal attribution and a separately planned
path-controlled experiment; neither a significance label nor a favorable rerun
alone establishes a code effect. Shared-path diagnostics must record that altered
isolation policy and account for cache/carryover effects.

Choose endpoints, practical threshold, confidence, process count and analysis
settings before the comparison. An **independent pilot** can inform a fixed
repeat count and plausible block length. Do not keep sampling until the desired
label appears, choose thresholds from observed effects, or repeatedly test a
changing workload family without a new analysis plan. A reproducible seed
reproduces schedule/resampling choices, not CPU noise.

### Descriptives and estimands

The experimental unit is one complete fresh-process workload observation. A
burst is one observation; its keys, lines and frames are not independent
replicates. Times remain nanoseconds in JSON; human reports use explicit,
readable latency units (the extended plain view uses milliseconds). `--details`
and JSON expose each target's count, mean, median, **sample** SD (`n-1`, null at
`n=1`), unscaled median absolute deviation (MAD), min/max, p90 and p95. Quantiles use
linear interpolation at `(n-1)*p`. p90 is labeled low-support below 50 successful
processes, p95 below 100; p99 is omitted below 1,000. These empirical tail
quantiles have no reported tail confidence interval and are especially unstable
at default sample counts. More bootstrap draws cannot create more tail data.

For complete successful pairs `b_i` (baseline) and `c_i` (candidate), the primary
relative effect is

\[
R = \exp\left(\frac{1}{n}\sum_i[\log(c_i)-\log(b_i)]\right),
\qquad \%\Delta = 100(R-1).
\]

This is the geometric mean paired candidate/baseline ratio, **not** a ratio of
medians, a ratio of means, an arithmetic average of percentages, or an aggregate
across workloads. Smaller means faster. The companion absolute effect is the
mean paired difference `D = mean(c_i - b_i)` in nanoseconds. This helps distinguish
a large ratio on a tiny floor-limited action from a material absolute delay.

### Circular moving-block bootstrap

Target median intervals and paired `R`/`D` intervals use a **fixed-length circular
moving-block percentile bootstrap** over chronological observations/pairs. Draw
block starts uniformly, copy `L` successive indices with wraparound, concatenate
blocks and truncate the last block to obtain exactly `n` indices. The same drawn
indices feed both targets, the paired log-ratio mean, and the paired absolute
difference. Transform log-mean interval endpoints back with `exp` for the ratio.
This preserves pairing and within-block chronology rather than independently
resampling baseline and candidate survivors.

`run` defaults to `--resamples 20000`, `--confidence 0.95`,
`--practical 0.05`, and `--seed 20261020`. Before observations begin, it stores
`manifest.metadata.analysis_plan` with exactly `resamples`, `confidence`,
`practical`, `seed` and `block_length` (null means the default length heuristic).
An option-free `report` inherits **all five** recorded settings. Explicit
report analysis flags are labeled sensitivity overrides, including values equal
to the original plan. A legacy journal without this optional plan falls back to
the current API defaults plus its manifest seed and is explicitly labeled as
having no recorded pre-acquisition plan. The Python `analyze` API itself keeps
its explicit/default parameters (seed 20261020); it does not implicitly inherit
an arbitrary metadata plan.
Default `L = ceil(n^(1/3))`; `--block-length` can specify an integer from 1
through `n`. `L=1` is ordinary independent-index resampling. `L=n` only rotates
the observed series, so the engine **suppresses every inferential interval and
practical decision**, not merely a warning beside a misleading zero-width CI.
Successful acquisition stays valid and paired point effects remain descriptive;
paired decisions are `exploratory` regardless of process count. This also covers
`n=1` and the unchanged heuristic's `n=2, L=2` case. Requested resamples remain
recorded, but `resamples_per_valid_workload` is zero and `intervals_available`
is false. Increasing resamples cannot restore missing sampling variation.
The cube-root default is a transparent heuristic, **not an optimal-length result
for Neovim**. A workload's
RNG stream is `random.Random("poincare-benchmark/v1:<seed>:<workload>")`, so exact
replay with the same engine/settings is deterministic and a failed sibling
workload does not consume another workload's random stream.

Intervals are approximate, conditional on this host/corpus/cache/environment
and a short-range temporal-dependence/stationarity model. Strong drift,
long-memory effects, multimodal state changes, very few independent blocks or
small process counts can make percentile coverage poor. These are fixed-length
circular blocks, **not the random-length stationary bootstrap**. Neither a large
resample count nor randomization gives a universal finite-sample coverage
guarantee.

### Multiplicity, Monte Carlo support, and decisions

Let `m` be the number of **all selected catalog endpoints**, including invalid
ones and calibration if selected, and let `alpha = 1-confidence`. Each interval
uses tail probability `alpha/(2*m)`, hence per-workload confidence
`1-alpha/m`. The nominal family target refers to the preselected primary paired
ratio endpoints (or candidate medians in a single-target run), recorded as
`statistics.primary_endpoint`. Median and absolute-effect intervals in a paired
run are secondary summaries shown at the same adjusted level; this does **not**
additionally guarantee joint coverage over every displayed statistic
(`statistics.secondary_interval_scope`). Bonferroni does not repair bad
per-workload bootstrap intervals. There are no p-value claims or aggregate score.

The report records requested `B`, resamples applied per valid workload, `L`,
seed, family size, adjusted level and expected bootstrap draws in each adjusted
tail, `effective_B*alpha/(2*m)`. When resampling is available, fewer than **20
expected draws per tail** produces an inadequate-tail-support warning and
**suppresses every practical decision as `exploratory`**, even with 20 or more
successful pairs. Point effects and intervals remain available, but the
intervals are explicitly flagged as underresolved on each workload. This is a
transparent Monte Carlo resolution gate, not a guarantee that 20 is sufficient
for coverage. Increase resamples as a predeclared analysis choice when the
family is large. At 95% confidence, 20,000 draws and all 27 endpoints give only
about 18.5 draws per tail, so practical decisions are suppressed; the default
19-endpoint core family gives about 26.3. Complete failure-free acquisition
remains valid regardless of this inference gate.

A paired workload receives a practical decision only after **at least 20
successful measured pairs, no failed warmups, an available nondegenerate
ratio interval, and at least 20 expected bootstrap draws per adjusted tail**.
With practical fraction `p` (default 0.05) and interval `[lo, hi]`:

| Condition | Label |
| --- | --- |
| `lo > 1+p` | `regression` |
| `hi < 1-p` | `improvement` |
| Entire interval within `[1-p, 1+p]` | `within practical band` |
| Otherwise | `inconclusive` |

Fewer pairs or inadequate adjusted-tail support are `exploratory`, even if the interval is narrow. Single-target
runs are `descriptive`, not a claim of improvement or no regression. "Within
practical band" is conditional evidence at the selected resolution, not proof
of identical performance; "inconclusive" is not equivalent to no regression.
Any error/timeout in **either phase or either target** makes that workload
`invalid`: no median inferential intervals and no paired point comparison or
intervals are returned. Successful-only descriptives are explicitly labeled;
there is no survivor inference, imputation of a timeout bound, or censor-adjusted
latency model. Failures remain operational outcomes requiring inspection.

Lag-1 Pearson association and equal-size first-versus-last-half mean difference
are **descriptive serial/drift diagnostics**, not hypothesis tests or automatic
sample-quality gates. For odd counts the middle observation is omitted from the
two half means, and that fact is recorded. Constant/too-short series have a null
lag correlation. Pair log-ratio and absolute-difference diagnostics are retained
in JSON. Missing measured successes suppress serial diagnostics rather than
pretending surviving processes were adjacent. Drift does not trigger deletion,
a retry, or extra samples; investigate under a separately planned experiment.

## Journal and replay contract

Acquisition writes JSONL incrementally:

1. One `manifest` with format `poincare-benchmark/v1`, integer seed/repeat/warmups,
   targets `['candidate']` or `['baseline', 'candidate']`, unique workload catalog,
   metadata, and the full ordered schedule.
   Newly collected manifests also store the analysis plan before the first
   observation; absence in a legacy v1 journal is not silently presented as a
   predeclared plan.
2. Exactly one `observation` per schedule entry, in that exact order, identified
   by phase (`warmup`/`measure`), zero-based block, workload, and target. Status is
   `ok`, `error` or `timeout`. `ok` requires a positive finite integer
   `latency_ns` and null `error`; failed/timeout observations have null
   `latency_ns`, retain their string-or-null error, and can retain `elapsed_ns`
   as **unscored** failure evidence.
3. Exactly one terminal `end` record with `complete: true` after the entire
   schedule was collected. This marker denotes complete acquisition, **not** that
   every observation succeeded.

For failed nonstartup observations, `unscored_last_oracle` can retain one
best-effort last observer snapshot with `captured_at_perf_ns` and an explicit
post-failure `boundary`. It is diagnostic state, not a retry, successful
completion, or substitute latency. Likewise,
`late_completions_outside_boundary` preserves notifications arriving during
post-failure evidence capture without making them scored successes. The original
status/null latency and whole-workload invalidation remain unchanged.

Replay requires the complete Cartesian schedule for both phases, every block,
workload and target, chronological phase/round order, adjacent balanced pairs,
and exact matching observations. Duplicate/missing/extra observations or end
markers, interrupted/truncated files, malformed JSON, duplicate object keys,
blank lines, nonfinite numbers, boolean-as-integer timings, and non-JSON evidence
are errors, not data to filter away. Numeric evidence must fit finite numeric
analysis; unrepresentable statistical results fail clearly instead of emitting
NaN or infinity. An interrupted journal is useful raw forensic evidence but
cannot become a completed report by dropping its last line or failed samples.

The standard-library-only API is:

```python
from pathlib import Path
from scripts.benchmark_display import print_report
from scripts.benchmark_stats import BenchmarkDataError, analyze, load_records

records = load_records(Path("comparison.jsonl"))
report = analyze(records, resamples=100000, confidence=0.95, practical=0.05,
                 seed=20261020, block_length=None)
print_report(report)                    # concise; Rich only on a supported TTY
print_report(report, plain=True, details=True)  # alternate full statistical view
```

`print_report(report, *, plain=False, details=False, file=None, width=None)` resolves
stdout at call time and accepts a stream/width for embedding. It does not mutate
the report or recursively copy retained host/screens/failure evidence. The
standard-library `benchmark_stats.render(report)` API remains the extended text
renderer; JSON is the complete structured representation, including provenance.

`load_records` decodes finite JSON objects and requires a valid manifest/end
envelope; it does not claim the intervening experiment is valid. `analyze`
performs the full schedule/observation schema validation once per call, including
when the decoded mutable records were edited by a caller. The CLI always calls
both in that order. Malformed/incomplete evidence or invalid analysis parameters
raise `BenchmarkDataError(ValueError)`.
The report format is `poincare-benchmark-analysis/v1`. Its top-level `valid` is a
boolean for complete failure-free acquisition; a failed selected workload makes
it false even if other workloads have valid results. Per-workload `valid`,
`decision`, per-target phase/status counts and descriptives, nullable intervals,
paired comparison, full failure records and warnings remain available.

The CLI additionally exposes `analysis_overrides` with `stored_plan` (or null),
`effective_plan`, and explicitly supplied replay `overrides`. Text output
labels sensitivity overrides and missing recorded plans. Original `run` choices
declare the stored plan and have an empty overrides object; replay flags remain
visible even when equal to recorded values. `statistics` exposes actual resolved
numeric settings, including the effective block length and interval availability.

JSON contains finite floats or null, never NaN. Changing replay confidence,
resamples, practical threshold or block length changes analysis, **not the
acquired sample size or the original schedule**; record and justify such choices
rather than presenting opportunistically selected analyses as preplanned.

## Verification scope

The final Python regression suite passed all 150 tests. A real nine-observation
run compared 58 stderr writes against the
successful scored intervals; no write fell inside a scored window. Real Ctrl-C
interruption returned 130 and restored the cursor, and JSON stdout stayed
separate from stderr progress. Report layouts were exercised at 48, 80, 100, and
120 columns.
An early missing-Nix failure returned 2, stopped with zero saved attempts, and
did not claim a journal existed. A real missing-Selene run retained one failed
observation, returned 1, restored the cursor, and kept JSON stdout clean.
Standard-library-only replay, ANSI-free plain output, the detailed terminal view,
and unchanged JSON with presentation flags were also exercised.

These are functional/UI and analysis-regression checks—not universal statistical
validation, a cross-revision performance result, or evidence of zero
instrumentation/renderer overhead. Re-run the relevant workloads and analysis
plan when the package, tool versions, fixture, observer, or environment changes.

## Scope not represented by this corpus

No empirical user-interaction frequencies or real-world monorepo distribution
were supplied; there is no defensible universal weighting or throughput score.
These experiments do not establish performance for Rust analyzer/Cargo indexing,
Nix evaluation, Fish LSP, SQL/Dadbod against a real database, JJ repository
restoration, terminal/tmux boundary crossings, remote filesystems, physical
terminal/compositor/GPU rendering, persistent warm language-server indexes,
very large generated/binary files, or hours-long sessions/memory leaks. Those
need their actual projects/services/hardware, explicit first-use versus primed
state and readiness oracles, and an independently fixed experiment design.
They are not implemented workload names or promised substitutes here. Python
coverage is deliberately syntax editing, not an undeclared language server.

## Methodology references

- NIST/SEMATECH, [Randomized block designs](https://www.itl.nist.gov/div898/handbook/pri/section3/pri332.htm):
  block controllable nuisance conditions and randomize what cannot be controlled.
  Adjacent time blocks reduce nuisance exposure; they do not freeze a host.
- D. N. Politis and J. P. Romano, [A Circular Block-Resampling Procedure for
  Stationary Data](https://statistics.stanford.edu/technical-reports/circular-block-resampling-procedure-stationary-data),
  Stanford report EFS NSF 370, March 1991 ([repository record](https://purl.stanford.edu/xh812zd4638)).
  The present finite fixture/process experiment and cube-root heuristic do not
  inherit a blanket finite-sample guarantee from that methodology.
