# Performance investigation — 2026-10-23

## Scope and experiment policy

Starting source: `326711d4` (working copy initially empty). Existing divergent jj
changes and conflicted `main` bookmarks were left alone. `Justfile` calls the
workload recipe **`bench`**, not `benchmark`.

The repository was surveyed before selecting a candidate: configuration startup,
all production Lua modules, language specifications and LSP configurations,
queries, Nix packaging/patches, workload acquisition/statistics/transport,
diagnostic profiling, size-note tooling, and the active and legacy test paths.
Two independent read-only surveys covered interaction/VC/persistence and
language/parser/formatter paths; findings were checked against the acquired
runtime rather than trusting the pre-existing `result` symlink.

Prioritisation follows the [HCI response-time guidance](https://www.nngroup.com/articles/response-times-3-important-limits/):
roughly 100 ms for an instantaneous response, 1 s for uninterrupted navigation,
and 10 s for maintaining attention. These are guides, not discontinuous pass/fail
limits. Frequent blocking editing work matters more than an equal delay in an
optional annotation. No user-action frequency data was supplied, so there is no
invented weighted score.

Measurements use the unchanged workload oracles and real attached remote UI.
The endpoint includes semantic checking and forced redraw, **not physical display
latency**. No overhead subtraction, outlier removal, retries, disabled features,
workspace exclusions, or shifted readiness boundaries were used. OS page cache,
CPU governor/temperature and other desktop activity were not controlled.
Initial load average was 4.17/3.61/3.46 on 16 logical CPUs. Adjacent randomized
AB/BA pairs control some temporal variation but cannot eliminate these limits.

## Baseline

Host: Ryzen 7 5800X, Linux 7.2.11-cachyos, Python 3.14.7; all 16 CPUs available.
Neovim: `v0.13.0-nightly+d039f19`, Release, LuaJIT 2.1.1785763465.
Baseline package: `/nix/store/7n6xsa5xrcfbg9639dqqx4d7cb7a44ds-poincare`.
Wrapper SHA-256: `680d974c142e1ec7b25f6393e434427d2e27fe18f6ac925e452bd60ee96b7ee4`.
LuaLS: 3.19.1. External tools came from the same `nix develop` environment.
Optional missing SQL/Fish/Rust tools generated warnings; they were not suppressed.
In particular, this environment does not exercise Rust-analyzer readiness.

Evidence directory: `/tmp/poincare-opt-20261023-yu72eg1q`.
Raw journals include fixture hashes, schedules, runtime/tool identities, UI grids,
oracle results and failures. This directory is local evidence, not a portable
package or permanent backup. The durable findings and measurements are recorded
here; `scripts/BENCHMARKS.md` defines the journal and timing contracts.

```sh
nix build .#poincare --out-link "$E/baseline"
just bench run --nvim "$E/baseline/bin/nvim" --suite all \
  --repeat 30 --warmups 3 --resamples 100000 --confidence 0.95 \
  --practical 0.05 --seed 20261023 --output "$E/baseline-all.jsonl" --plain
```

All **891/891 observations passed**. Warm state means reused isolated HOME/XDG
per target/workload, with a fresh editor process each time, not a warm editor.
Intervals below are moving-block bootstrap median intervals, adjusted across
27 endpoints for a 95% family target. Thirty observations do not reliably resolve
p95; no tail-performance claim is made.

| Workload | Median ms | Adjusted median interval ms | Priority/interpretation |
| --- | ---: | --- | --- |
| startup-empty | 44.51 | 43.86–45.76 | Below 100 ms; startup only |
| startup-file | 83.87 | 83.36–85.44 | Startup near instantaneous boundary |
| open-python | 57.59 | 57.08–58.48 | First language/query setup |
| open-rust | 95.33 | 94.19–96.50 | Near 100 ms; no Rust LSP readiness |
| open-nix | 46.02 | 45.06–46.59 | Below 100 ms |
| open-large | 60.91 | 60.10–61.38 | File ready, not syntax-color ready |
| open-large-highlighted | 138.40 | 136.90–140.50 | Perceptible syntax-readiness delay |
| edit-insert | 3.297 | 3.103–3.502 | Frequent, already short |
| edit-paste-undo | 21.09 | 20.56–22.30 | Composite paste/check/undo |
| treesitter-motion | 11.05 | 10.80–11.47 | Already short |
| folds | 11.46 | 10.85–11.79 | Already row-query-based |
| scroll | 11.94 | 11.62–12.31 | Four-motion burst |
| buffer-switch | 15.95 | 15.04–16.32 | Includes UI/VC hooks |
| split-resize | 18.75 | 18.01–19.45 | Internal splits; not tmux |
| completion-buffer | 52.17 | 51.81–53.35 | Includes intentional 30 ms debounce |
| picker-files-first | 21.79 | 21.11–23.69 | Lazy first use |
| picker-files-repeat | 13.72 | 13.31–14.20 | Primed within fresh process |
| picker-grep | 23.46 | 22.21–24.80 | Real backend |
| git-gutter | 0.7859 | 0.7141–0.9101 | Small-file change; not large editing |
| git-blame | 154.40 | 154.10–154.50 | Includes intentional 150 ms debounce |
| pins-select | 11.53 | 11.04–14.20 | Not session restoration |
| format-save-lua | 11.36 | 11.05–11.75 | Small changed file |
| lint-lua | 21.67 | 21.47–22.73 | Edit/save-to-diagnostic |
| lsp-lua-ready | 52.66 | 52.31–53.39 | Attach, not workspace readiness |
| lsp-definition | 884.50 | 699.40–888.80 | Highest navigation latency |
| completion-lsp-indexed | 15.08 | 14.77–15.19 | Explicit completion after definition barrier |
| redraw-control | 0.2574 | 0.2438–0.2696 | Instrumentation diagnostic, not user action |

## Architecture and causal attribution

- `src/init.lua` assembles UI, picking, parsers, completion, language mechanisms,
  surrounding/pairing, pins and tab behaviour. Nix provides immutable plugin,
  parser and query paths. Most lazy loading is implemented with lz.n.
- Language specs select available tools at startup. Formatting synchronously
  completes before the disk write; linting runs after reads/writes/filetype events.
  Parser/highlight/fold lifecycle is native Neovim. Python has no folding spec.
- `src/lua/lang/modules/fold.lua` already queries each header row once per active
  tree and resolves capture intervals. It does not parse or cache the buffer.
  Per-byte highlighting or a full-buffer foldtext parse is not the current cause.
- Lua `gd` calls native definition directly. Ordinary projects already get an
  empty `workspace.library`; Neovim runtime libraries are opt-in outside the
  exact configuration root. Definition preparation waits for attachment only;
  indexed-completion preparation intentionally has a stronger barrier.
- Instrumented real UI runs attributed Rust opening to **60.67 ms in three native
  query compilations**, including a 42.81 ms highlight query. Python samples
  similarly concentrate in query construction; large Python adds about 68 samples
  at 1 ms cadence inside root parsing. These are diagnostic, instrumented runs,
  not estimates of an isolated additive portion of the scored baseline.
- LuaLS logs show client configuration at 07:42:51.691, preload starting at
  07:42:52.003, file loading at .210, and completion at .522. It loaded 279 files
  including built-in metadata and 261 project Lua files. The baseline definition
  distribution has modes around 695–706 and 882–893 ms. Upstream workspace reload,
  preload, inter-scope coordination and load-completion polling contain 100 ms
  waits (`script/workspace/{workspace,loading}.lua`). No owned mapping delay was
  found. Narrowing the workspace or prewarming definitions would change the work.
- Diagnostic headless startup profiling (10 repeats, 2 warmups) gave 39.76 ms mean
  process lifetime and 42.99 ms instrumented lifetime. Import/configuration costs
  are spread across modules; `icons` includes the first native LSP import. These
  numbers are not directly comparable to attached-UI startup latency.
- Gutter rendering synchronously serializes/diffs the full buffer and replaces
  marks. Blame serializes after its 150 ms debounce and runs asynchronously.
  Statusline project-root lookup is uncached; diagnostic counts/client names are
  recomputed per render. VC status has root/status/pending caches and coalescing.
- Real process instrumentation observed two `git show` calls per initial open,
  and two Clippy launches for Rust through FileType/lz.n replay. The first Lua
  open observed one Selene launch, not two; the lint edit/save scenario observed
  one initial and one post-save launch. Thus a blanket claim of duplicate first
  Lua linting would be wrong. Cancellation/identity guards are correctness-critical.

## Rejected and deferred hypotheses

### Built-in Lua loader cache: rejected pilot

A temporary wrapper enabled `vim.loader.enable()` before configuration.
Twelve measured adjacent pairs plus three warmups, four selected endpoints,
20,000 resamples, seed 20261024 were collected for each state policy.
These are **exploratory pilots**, not the suite's minimum-20-pair verdicts.

| Endpoint | Warm paired change | Fresh-cache paired change |
| --- | ---: | ---: |
| startup-empty | −10.2% | +19.9% |
| startup-file | −8.52% | +11.3% |
| open-python | −1.61% | +1.22% |
| picker-files-first | −11.5% | −2.69% |

Warm startup medians improved from 44.27→40.20 ms and 83.33→76.58 ms;
fresh-cache startup became 44.29→53.07 ms and 83.75→92.76 ms. The change shifts
cost to cache creation, adds an experimental loader, and does not address native
query compilation. No loader change was retained.
Journals: `loader-pilot-{warm,fresh}.jsonl`.

### Higher-latency paths without a safe owned-code shortcut

- Do not lower blame/completion debounce merely to improve a score: these bound
  work/flicker during typing and movement. Indexed completion bypasses automatic
  completion debounce anyway.
- Do not disable large-file highlighting/folds, force synchronous root parsing,
  or precompile every query during startup. Those remove behaviour or move cost;
  viewport ranges only bound injected parsing, not whole-root parsing.
- Rust root resolution does synchronously probe Cargo sysroot before cheap
  library-prefix checks, but Rust-analyzer is absent in the acquired environment.
  This cannot explain the measured Rust-open result. Toolchain/cwd-aware real
  Rust-project evidence is required before changing reuse/root semantics.
- Deep/slow-filesystem statusline lookup, diagnostic-heavy redraws, large-file
  gutter editing, tmux integration and large Git/JJ workspaces remain coverage
  gaps. Synthetic shallow/local results do not establish their end-to-end cost.
  Caching requires rename/cwd/marker/index/diagnostic invalidation; extra caches
  are not justified merely by a static O(n) observation.
- The legacy `tests/linters.lua` is intentionally not collected. Active first-lint
  regressions cover real Selene. The Bombadil lint fixture uses `lint` in the
  recipe but `linters` in its oracle/spec; it was not used as validation.

## Formatter no-op experiment

Hypothesis: after all safety/staleness checks, byte-identical output can return
without splitting it into a second line table or walking a deep equality check.
The existing normalized-line path remains necessary when bytes differ (including
CRLF/terminal-newline differences). No formatter invocation, timeout, disk write,
change detection, undo rule, or external-tool selection is removed.

A separately labelled experiment extends the existing real StyLua save scenario
with a canonical **24,002-line Lua file** (24,000 table-field assignments), retaining
whole-buffer and on-disk equality checks. It is not the standard small changed-file
endpoint, despite reusing its harness implementation. Its corpus schema is
`poincare-large-noop-save-experiment/v1`. An independent 12-run pilot measured a
547.6 ms median (exploratory interval 518.6–568.2 ms); this is a perceptibly blocking
save path. The fixed comparison uses 60 pairs, 3 warmups, 100,000 resamples,
95% confidence, 1% practical band, seed 20261026. A retained result must also
support an absolute saving of at least 5 ms and preserve normal-save behaviour.

The comparison stopped after 60/126 saved observations with `ENOSPC`: the 16 GiB
`/tmp` tmpfs filled with **Selene core dumps in both targets' fixture directories**.
The save oracle passed those observations, but it does not establish background
linter health. `file` identified the cores as Selene 0.31.0; the cause of its crash
was not established. The incomplete journal is not analyzed for improvement.
Representative baseline/candidate cores and the initial evidence are archived at
`~/.local/state/poincare/benchmarks/20261023-yu72eg1q/`.
Generated failure workspace/core files were removed after archiving, restoring
scratch space. The four-line formatter fast path was **reverted**, not retained
on theoretical allocation savings. The normal-save comparison chained after it
did not run.

## Same-turn lint coalescing

Hypothesis: `FileType`, lazy-load replay and `BufReadPost` can describe the same
buffer activation, yet each calls `try_lint`, canceling and replacing work.
A per-buffer pending flag plus `vim.schedule` should launch only once per event
loop turn, using the final current buffer contents/filetype. No timed debounce,
result cache or suppression of later reads/writes is needed. Unloaded buffers
must be skipped, and execution must remain in the target buffer's context.
The fixed comparison selects startup-file, open-rust, open-nix, lint-lua and
format-save-lua: 60 pairs, 3 warmups, 100,000 resamples, 95% confidence, 5%
practical band, seed 20261027. Process-count evidence is separate from timing.

The focused comparison completed **630/630 successful observations**:

| Endpoint | Baseline median ms | Candidate median ms | Paired change, adjusted interval |
| --- | ---: | ---: | --- |
| startup-file | 84.34 | 80.86 | −3.83% [−4.69%, −2.79%] |
| open-rust | 96.06 | 91.51 | −4.57% [−5.26%, −3.98%] |
| open-nix | 45.86 | 42.16 | −7.97% [−9.63%, −6.42%] |
| format-save-lua | 11.27 | 11.51 | +2.33% [−0.328%, +5.36%] |
| lint-lua | 22.34 | 22.39 | +1.21% [−0.463%, +2.90%] |

Nix opening meets the predeclared practical-improvement criterion. Rust's
improvement is supported but its interval straddles the 5% practical boundary;
it must not be labelled a resolved >5% gain. Mean paired savings were 3.666 ms
[2.922, 4.486] for Nix and 4.396 ms [3.811, 5.081] for Rust. Small-file formatting
is inconclusive at ±5%, with a mean change of +0.271 ms [−0.040, +0.615];
lint-on-save is within ±5%. No tail claim is made.

Instrumented attached-UI execution confirmed **Clippy launches decreased from
two to one** on Rust opening. The candidate runs each Nix linter once and retains
one initial plus one post-save Selene launch. Native query compilation remained
about 60 ms on Rust, so this does not claim to solve that separate bottleneck.

Verification: `just test` passed all **59 isolated regression cases and 54 unit
cases**, including a new real-Selene regression for queued hidden buffers and
deletion before dispatch. A separate packaged-editor smoke passed two queued
buffers, deleted pending buffer, clean save, subsequent dirty save and filetype
transitions. The benchmark itself exercised the attached UI, real formatter and
real diagnostics. Expected sandbox read-only probes and optional-tool warnings
were not hidden; some pre-existing fixture cleanup paths also emitted E211 while
all cases passed.

Retain this focused change: it removes duplicate work without tool-specific
logic, caches, fixed waits or stale-content keys. The broader comparison uses
all 27 original endpoints, 30 pairs, 3 warmups, 100,000 resamples, 95% confidence,
5% practical band and seed 20261028 (`lint-all-paired.jsonl`).

The broader run completed **1,782/1,782 successful observations**. Nix opening
again met the >5% improvement criterion: 43.54→40.14 ms, paired −7.89%
[−10.0%, −5.82%]. Rust was 93.04→87.40 ms, paired −6.04%
[−7.40%, −4.48%]; all 30 Rust candidate observations were faster than their
adjacent baselines, but the adjusted interval still straddles the 5% cutoff.
No endpoint was classified as a regression. **That is not proof of no regression**:
many short endpoints and first-definition navigation remain inconclusive.

In particular, one candidate startup-file observation was 284.06 ms versus
83.27 ms for its paired baseline. It contained a real acknowledged startup
warning prompt; causation of the extra delay was not established. It was retained
in the analysis, leaving startup-file's paired interval wide despite its lower
76.69 ms median versus 80.16 ms. First-definition results still switch between
roughly 680 and 887 ms, with paired differences near ±100/200 ms; the paired
effect was +4.13% [−4.12%, +13.6%], not a resolved regression or improvement.
Large-file highlighted readiness stayed within ±5% (134.4→134.1 ms).

## Global reassessment and Git-index experiment

After lint coalescing, the highest delays remain upstream LuaLS readiness,
whole-root large-file parsing and first-use native query compilation. The
retained change has not altered those boundaries or disabled those services.
Most frequent small editing/navigation actions remain below 25 ms. The remaining
owned-code opportunity with direct execution evidence is the duplicate `git show`
from `BufReadPost` followed by `BufEnter`.

Hypothesis: schedule only the read-event refresh, remembering the current request
identity. If entry/rename/focus already replaced that request, skip the scheduled
read; otherwise refresh a reread normally. Keep the other events synchronous and
retain all existing stale-result, root/path, empty-file and failure semantics.
This avoids a new persistent cache or broad freshness policy.

The fixed comparison uses the retained lint package as baseline, not the original:
startup-file, open-python, open-rust, open-nix, buffer-switch, pins-select and
git-gutter; 60 pairs, 3 warmups, 100,000 resamples, 95% confidence, 5% practical
band, seed 20261029 (`gutter-paired.jsonl`). Elimination of a process alone is not
enough to retain extra lifecycle logic without a worthwhile measured result.

All **882/882 observations passed**, but no endpoint met the predeclared >5%
practical-improvement criterion:

| Endpoint | Lint-only median ms | Index candidate median ms | Paired change, adjusted interval |
| --- | ---: | ---: | --- |
| startup-file | 77.29 | 75.01 | −2.57% [−3.67%, −1.30%] |
| open-python | 55.49 | 53.69 | −3.80% [−5.00%, −2.60%] |
| open-rust | 89.03 | 86.37 | −2.74% [−3.32%, −2.14%] |
| open-nix | 40.18 | 38.72 | −3.46% [−4.43%, −2.37%] |
| buffer-switch | 15.00 | 15.40 | +3.82% [−0.823%, +8.79%] |
| git-gutter | 0.7846 | 0.7898 | −0.191% [−7.40%, +6.99%] |
| pins-select | 10.91 | 11.66 | +5.06% [−2.27%, +12.9%] |

Opening gains are real but small (roughly 1.5–2.7 ms in these medians).
Buffer switching and pin selection remain inconclusive in the slower direction.
**Reverted**: this does not justify adding another event-ordering rule. No gutter
production or test changes are retained, and no correctness-suite claim is made
for this rejected candidate beyond its successful benchmark oracles.

## Stopping decision

One production optimisation is retained: same-turn lint request coalescing, with
real diagnostic lifecycle coverage. Loader caching, the formatter no-op shortcut
and deferred index reads are not retained. Source, fixtures, endpoint definitions,
external-tool selection, intentional delays, native parsing and LSP semantics
otherwise remain unchanged.

The repository-wide ranking was revisited after attribution, the rejected loader
pilot, the invalid large-save comparison, the retained lint change, the complete
paired suite and the index-read experiment. Further changes lack a combination of
demonstrated end-to-end value and a low-risk maintainable implementation:

1. First Lua definition is the largest navigation delay, but is dominated by
   external-server readiness/scheduling. An upstream server fix needs its own
   readiness/cancellation/multi-scope evidence, not exclusions or timing changes.
2. Large-file syntax is above 100 ms; native root parsing/query construction is
   measured work. Disabling it, blocking the editor longer or moving compilation
   into startup is not a free improvement.
3. Remaining owned paths either already respond well below 100 ms or need real
   deep/remote filesystems, large repositories, long-lived sessions, diagnostic
   loads or toolchains not represented here. Broad cache machinery is unjustified
   without those measurements.
4. The 30-run full comparison leaves tails and several regression intervals
   unresolved. Measurements were not extended selectively until desirable labels
   appeared. They support the retained Nix/Rust opening improvements, not a claim
   of universally unchanged/faster behaviour.

The raw evidence, instrumented diagnostics, rejected experiment drivers and
representative Selene cores are preserved outside the repository at
`~/.local/state/poincare/benchmarks/20261023-yu72eg1q/`. Temporary experiment
drivers are not production additions. Existing user artifacts and jj bookmark
conflicts were not removed or resolved.

Final checks after formatting the two retained Lua files: both first-lint
regressions passed (2 cases each); `just benchmark-test` passed all **105 Python
tests**. The queued-buffer test now switches to an empty buffer before cleanup,
avoiding selection of a prior test's already-deleted fixture. Production formatter
and gutter files were restored exactly after their rejected experiments.

The durable evidence directory contains `evidence-complete.tar.gz` (all journals,
diagnostic output and temporary drivers), `evidence-initial.tar.gz` (the checkpoint
at the interrupted large-save experiment), and `selene-cores.tar.gz` (one core
from each target). Its `baseline` and `lint-candidate` links are registered Nix GC
roots for the exact measured packages, so comparisons do not depend on `result`
or a later package rebuild. The `/tmp` experiment and smoke directories were
removed only after successful archiving and archive-integrity checks.
