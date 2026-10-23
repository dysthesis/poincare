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

## 2026-10-24 follow-up: broader coverage and identical-buffer diffing

### Acquisition and repository-wide reassessment

Starting source: `cfee578c`, with an empty working copy. The existing lint
coalescing optimisation and all prior findings above were retained as the
starting point, not credited again. The workload recipe remains `just bench`;
there is no `benchmark` recipe.

The fresh survey covered the runtime entrypoint, all production Lua modules,
language specifications/server configurations/queries, Nix packaging and native
patches, active/legacy tests, benchmark acquisition/transport/statistics/display,
headless profiling, and size/history tooling. Two independent read-only surveys
covered UI/VC/persistence and language/parser/plugin paths. Their findings were
synthesized with the measured paths:

- Startup assembles thin plugin configuration and language mechanisms; Nix
  supplies immutable plugin/parser/query paths. No new loader or eager query
  prewarming was introduced.
- Gutter rendering synchronously materializes the entire buffer, diffs against
  the current index snapshot, and replaces signs. Its request identity and
  path/root guards remain essential. Existing small-file benchmarks do not
  represent large tracked-file editing.
- Blame serializes unsaved contents after its intentional 150 ms debounce;
  Git/JJ subprocess work is asynchronous. VC status already caches/coalesces
  repository requests. Pins persist at most ten new selections per project;
  split/tmux and tab behavior have separate interaction contracts.
- Statusline project-root lookup is uncached; diagnostic counts and client
  names are recomputed on render. Static complexity alone does not justify a
  filesystem or diagnostic cache.
- Formatting blocks the write and preserves hunk positions, metadata and undo.
  Linting already coalesces same-turn events. Foldtext queries header rows in
  active trees without a full-buffer parse of its own.
- The largest standard endpoints remain LuaLS workspace readiness and native
  parsing/query construction. Rust-analyzer is still unavailable in this
  environment, so its synchronous Cargo/sysroot resolver cannot explain the
  measured Rust-open endpoint.
- Benchmark preparation, package builds, report rendering, profiling and size
  notes are not editing latency. The remote-UI observer requests a checked
  forced redraw; physical display latency is not measured.
- The excluded legacy linter tests and mismatched Bombadil lint paths are not
  evidence of active linter correctness. The isolated real-tool regressions
  remain the applicable verification path.

Evidence directory:
`~/.local/state/poincare/benchmarks/20261024-optimization/`.
The `baseline` and `equal-candidate` links retain the measured packages as Nix GC
roots. Host/runtime: Ryzen 7 5800X, 16 logical CPUs, Linux 7.2.11-cachyos,
Python 3.14.7, Neovim `v0.13.0-nightly+d039f19`, Release, LuaJIT 2.1.1785763465.
Initial load average was 0.73/1.40/1.45. No CPU affinity, governor, thermal or
page-cache control was imposed; desktop activity remains an uncontrolled factor.
The same development-shell tool environment was used for both targets.

Baseline package: `/nix/store/f56ry441dsjsxhng7ag2qcgk2mmsqrq0-poincare`,
wrapper SHA-256
`d840d2aa2fc043d0f78573ab62bbc8f6f2f92396019de3f11086784b093680e9`.
Candidate package: `/nix/store/xk1m0394z5q9pl6qsfxmygsljdy0nxbd-poincare`,
wrapper SHA-256
`e3dee3178cc751cbd91d492c22a6e254069727907d4293950e1e43f49e61fd9c`.

Unlike the earlier study's `/tmp` tmpfs, these fixtures and isolated state live
on local Btrfs on the encrypted home filesystem. Save/lint timings therefore
must not be treated as a causal regression against yesterday's measurements.
No filesystem setting or production write policy was changed.

### Fresh full baseline and HCI ranking

```sh
E="$HOME/.local/state/poincare/benchmarks/20261024-optimization"
nix build .#poincare --out-link "$E/baseline"
just bench run --nvim "$E/baseline/bin/nvim" --suite all \
  --repeat 30 --warmups 3 --resamples 100000 --confidence 0.95 \
  --practical 0.05 --seed 20261024 --output "$E/baseline-all.jsonl" \
  --plain --no-progress
```

All **891/891 observations passed**. Warm state still means reused isolated
HOME/XDG with a fresh process per observation. The following median intervals
are adjusted across all 27 endpoints for the approximate 95% family target.
Thirty observations do not resolve tail latency reliably.

| Endpoint | Median ms | Adjusted median interval ms |
| --- | ---: | --- |
| startup-empty | 43.05 | 42.15–44.03 |
| startup-file | 77.77 | 76.29–79.98 |
| open-python | 55.71 | 55.31–56.32 |
| open-rust | 89.33 | 88.71–90.02 |
| open-nix | 40.44 | 39.43–41.39 |
| open-large | 58.58 | 57.70–60.41 |
| open-large-highlighted | 135.5 | 133.7–136.9 |
| edit-insert | 3.324 | 2.950–3.566 |
| edit-paste-undo | 20.22 | 19.68–20.83 |
| treesitter-motion | 10.62 | 10.13–10.96 |
| folds | 11.30 | 9.782–11.99 |
| scroll | 11.40 | 11.15–11.70 |
| buffer-switch | 15.00 | 14.21–16.57 |
| split-resize | 18.43 | 17.60–18.88 |
| completion-buffer | 51.27 | 50.23–51.87 |
| picker-files-first | 21.00 | 19.87–22.36 |
| picker-files-repeat | 13.78 | 13.28–14.59 |
| picker-grep | 21.94 | 21.61–23.00 |
| git-gutter | 0.8423 | 0.7234–1.016 |
| git-blame | 154.1 | 153.9–154.4 |
| pins-select | 11.09 | 10.26–12.02 |
| format-save-lua | 26.73 | 26.19–52.28 |
| lint-lua | 36.58 | 34.98–60.21 |
| lsp-lua-ready | 51.87 | 50.89–53.21 |
| lsp-definition | 881.4 | 785.5–883.0 |
| completion-lsp-indexed | 15.09 | 14.47–15.56 |
| redraw-control | 0.2851 | 0.2516–0.3099 |

Priority is not simply descending duration:

1. First definition approaches the 1 s continuity boundary; visible large-file
   syntax exceeds the roughly 100 ms instantaneous-response guide. They remain
   highest-impact measured delays, but the previous native/server attribution
   supplies no safe owned-code shortcut.
2. Repeated editing stalls can matter below 100 ms. Large tracked-file editing
   is an owned synchronous path absent from the original three-line gutter
   endpoint, making this a worthwhile independent coverage experiment.
3. Rust opening and file startup approach 100 ms; completion includes its
   intentional 30 ms debounce. No delay was reduced or work moved into preparation
   to improve a score.
4. Ordinary save/lint, picking, switching, folds, scrolling and insertion are
   below 100 ms here. Save is blocking; lint and VC subprocess completion are
   different concerns. Blame's 154 ms includes intentional debounce and is an
   annotation, not an equivalent 154 ms input stall.
5. Calibration is instrumentation evidence, not a user action. No empirical
   workload-frequency data exists, so there is still no weighted aggregate.

### Iteration 1: avoid diffing identical snapshots

The independent text-file pilots retain the three original gutter lines and
append distinct tracked lines, using the real Git index and unchanged dirty/edit
checks. Eight measured processes plus two warmups yielded exploratory medians
of **5.722 ms for 12,004 lines** and **39.82 ms for 100,000 lines**.
One instrumented 100,000-line edit recorded one native diff call taking
20.354 ms and gutter line retrieval taking 10.049 ms. This is diagnostic
attribution, not an additive decomposition of uninstrumented medians.

An initial pilot incorrectly replaced the oracle's hard-coded second line.
It timed out despite correct signs and was interrupted after nine saved failed
observations. `gutter-12k-pilot.jsonl` is incomplete invalid setup, not a
production failure or a usable timing sample. No failure was retried within a
scored schedule. The corrected driver passed an independent preflight before
new fixed pilots/comparisons were started.

Hypothesis, fixed before editing: after clearing old signs and serializing once,
if buffer bytes equal the index snapshot, return without invoking the native
diff. Otherwise preserve the existing diff options and all sign/lifecycle
behavior. This removes redundant work without a changedtick cache, debounce,
async race, alternate diff algorithm or size threshold.

The undo experiment moves the existing real `u`/`gutter-reset` step from untimed
preparation into the measured action, after proving a dirty sign. Its existing
oracle verifies no signs and exact whole-buffer restoration, then forces redraw.
Whole-buffer oracle reads remain included, so these are **not isolated undo
handler times**. This is explicitly a separate experiment, not a replacement
score for the standard dirty-edit endpoint. Journals retain the inherited
`git-gutter` catalog name/action description; the experiment description, actual
dispatched action and checked `gutter-reset` oracle distinguish undo from edit.

The fixed plan in `hypotheses.md` selected 60 adjacent balanced AB/BA pairs plus
three warmups for 12k undo, 100k undo and 100k dirty edit, seeds 2420/2421/2422,
100,000 resamples and a 5% practical band. Each comparison used confidence
`1 - 0.05/3`, adjusting the three-experiment primary family. Retention requires
a supported >5% improvement and at least 3 ms saving on 100k undo, no material
dirty-edit regression, and passing correctness checks.

All **378/378 observations passed**:

| Experiment | Baseline median ms | Candidate median ms | Paired change, adjusted interval |
| --- | ---: | ---: | --- |
| 12,004-line undo to clean | 5.281 | 3.314 | −37.92% [−39.74%, −36.26%] |
| 100,000-line undo to clean | 73.15 | 52.90 | −28.18% [−28.71%, −27.63%] |
| 100,000-line dirty edit | 31.53 | 31.71 | −0.116% [−1.418%, +0.978%] |

Mean paired savings are **20.712 ms [20.217, 21.219]** for 100k undo and
**2.048 ms [1.921, 2.208]** for 12k undo. Dirty edits are within ±5%; their mean
candidate-minus-baseline effect is −0.050 ms [−0.486, +0.308].
Paired log-ratio lag-1 associations were 0.141, −0.113 and −0.044 respectively;
these are diagnostics, not guarantees of stationarity or interval coverage.
The substantially different unpaired dirty-edit pilot and confirmatory medians
reinforce the need for adjacent comparisons rather than historical ratios.

The change is confined to `src/lua/ui/vc-gutter.lua::render`. The added
`tests/regressions/gutter-empty.lua` case checks dirty → undo-to-clean → redo,
including unchanged disk/index bytes. Existing tests cover zero-byte versus
one-newline buffers, EOL metadata, pre-write edits, index replacement, stale
success/failure, rename/root transitions, deletion and non-file buffers.
After formatting the two changed Lua files, `just test` passed **60 isolated
regression cases and 54 unit cases**; `just benchmark-test` passed **105 tests**.
Expected sandbox read-only probes, optional-tool warnings and pre-existing
fixture-cleanup E211 messages were not hidden.

### Broad validation and a completion regression signal

The fixed full paired run (`equal-all-paired.jsonl`, seed 2423) completed
**1,782/1,782 successful observations**, 30 pairs plus three warmups per
endpoint, 100,000 resamples, 95% family target across 27 endpoints and ±5%
practical band. Semantic success did **not** imply performance acceptance.
Twelve endpoints were within the practical band, fourteen were inconclusive,
and indexed completion was classified as a regression:

- `completion-lsp-indexed`: baseline/candidate medians 14.837/15.129 ms,
  paired **+47.37% [+11.08%, +89.40%]**, mean paired increase
  **11.794 ms [3.626, 18.854]**. Nine of thirty candidate observations entered
  a roughly 52–56 ms mode; no baseline observation exceeded 30 ms.
- First definition remained multimodal and inconclusive: 881.7/916.7 ms,
  paired +4.97% [−3.77%, +13.1%].
- Visible large-file syntax remained within ±5%: 133.3/133.3 ms,
  paired −0.20% [−1.29%, +0.736%].
- Startup, opening, ordinary formatting and attachment had intervals within
  ±5%. Several short editing endpoints were inconclusive, not proof of no
  regression.

The candidate was **not accepted from focused results alone**. The unexpected
completion mode triggered server/client source investigation and explicit
cross-over diagnostics. Separate fixed fixture/state paths are associated with
target labels in the ordinary suite; cross-over experiments must distinguish
binary effects from path-dependent server behavior. The original full-suite
result remains evidence and is not replaced by a favorable later result.

### Iteration 2: diagnostic-heavy UI reassessment

After the focused gutter improvement, the repository-wide ranking was revisited.
The remaining large delays still have the previously identified native/server
ownership; the equality guard does not solve dirty-buffer serialization/diffing.
The next owned repeated path investigated was diagnostic-heavy statusline redraw.

Two explicitly instrumented pilots published 1,000 and 10,000 deterministic
diagnostics through the real `vim.diagnostic.set` API, then ran the existing
four-motion Python scroll with its unchanged cursor/topline/redraw checks.
These are controlled rendering loads, **not real LSP diagnostic acquisition or
claims about typical user diagnostic counts**. Eight measured processes and two
warmups each passed. Medians were 9.824 ms and 19.88 ms; the median time inside
the six diagnostic-count calls was 0.403 ms and 3.578 ms respectively.
The native `_store.count` iterates diagnostics; it does not deep-copy the
public `vim.diagnostic.get` result.

Decision: **do not add a diagnostic-count cache**. This experiment does not
support a user-perceptible gain at 1,000 diagnostics, and even the 10,000-item
load spends only a few milliseconds counting across the whole four-motion
burst. A cache would add reset/multiple-namespace/buffer-lifetime invalidation
for limited demonstrated value. No production diagnostic code was changed.

### Completion cross-over resolution

The independent diagnostic design preserved the user action and definition
readiness barrier, wrapped RPC send/reply timestamps, and alternated both
editor binaries through the same two project/state locations. The first fixed
24-pair diagnostic on two new shared locations had no slow-mode observation;
paired +1.14% [−1.66%, +4.83%], within ±5% for that instrumented experiment.
That alone does not explain or invalidate the original regression signal.

The decisive next 24-pair diagnostic crossed both binaries through the **exact
original full-suite project and state paths**. All 52 observations including
warmups passed. Slow-mode counts (>30 ms, descriptive only; nothing filtered):

| Binary | Original baseline path pair | Original candidate path pair |
| --- | ---: | ---: |
| Baseline | 0/12 | 5/12 |
| Equality guard | 0/12 | 4/12 |

The excess delay followed the path/state pair, **not the editor binary**.
Slow samples dispatched completion roughly 4.5–7 ms after readiness, then
waited 44.7–48 ms for its reply instead of roughly 6 ms. Other post-edit
server replies were delayed together. The trace includes client transport and
dispatch, not isolated server CPU time. Project and HOME/XDG paths were crossed
together; this does not identify which component or internal server condition
caused the path sensitivity.

Source tracing confirmed explicit omnifunc completion bypasses the configured
30 ms automatic-completion timer. Native `Client:request` flushes pending text
changes before dispatch, rather than waiting the default 150 ms change debounce.
A separately armed automatic timer can issue a second request while the first
is outstanding; the observed slow first request was already dispatched, so this
does not justify attributing its delay to that timer. LuaLS checks workspace
readiness, reparses changed text as needed, and uses coroutine scheduling; no
fixed 40 ms delay was established from the completion handler itself.

A final **uninstrumented** fixed check used 60 adjacent pairs, three warmups,
100,000 resamples, seed 2432, 95% confidence and ±5% practical band. Within each
pair both binaries used the same exact project/state location; pairs alternated
between the two original locations. All **126/126 observations passed**.
Baseline/candidate medians were 15.19/14.85 ms; paired −7.28%
[−20.0%, +8.60%], **inconclusive**, not an equivalence or improvement claim.
Both binaries again showed the slow mode only on the original candidate path
(10/30 baseline and 6/30 candidate); neither did on the original baseline path.
State is deliberately shared in these diagnostics, unlike the standard suite.
Fresh editor/server processes, restored fixture content, actual paths and
cache-policy limitations are retained in the journals/driver; carryover is not
assumed absent.

Decision: the full-suite completion label is confounded with the path/state pair
and does not establish a gutter-induced regression. Retain the equality guard
for its separately demonstrated undo improvement and small implementation.
Do **not** claim full-suite equivalence: fourteen original endpoints and the
path-controlled completion comparison remain inconclusive, and tails remain
underresolved. The benchmark documentation now explicitly records this
target-path confound; no acquisition oracle, endpoint or production completion
behavior was changed to hide it.

### Follow-up stopping decision

One additional production optimisation is retained: exact-byte equality before
native gutter diffing. No previous optimisation is credited again. The new
behavior has a checked real-UI benefit, a dirty-edit control, an undo/redo
regression, and full correctness/broad-performance coverage with the limitations
above. It does not skip dirty-buffer work or change Git freshness semantics.

The global ranking was revisited after the new baseline, large-file attribution,
focused candidate comparisons, full-suite regression signal, diagnostic-heavy
scroll probes and completion cross-over investigation. Further changes do not
currently have comparable evidence-to-complexity value:

- Native large-file parsing/query compilation and first LuaLS definition remain
  the largest standard delays. Moving or disabling the work is not an
  optimisation; an upstream change requires its own semantic investigation.
- Dirty large-file edits still serialize and diff whole buffers. Incremental
  diff maintenance, asynchronous workers or delayed signs would introduce
  substantial invalidation/latency trade-offs not supported by the present
  clean-snapshot experiment.
- Diagnostic counting is measured but too small here to justify a new cache.
  Root lookup on slow/deep filesystems, Rust's actual Cargo/sysroot lifecycle,
  very large Git/JJ projects and tmux boundaries still lack representative
  environment evidence. Local synthetic scores cannot resolve those risks.
- The path-dependent LuaLS delay is reproducible with the unchanged baseline
  binary. Its exact upstream cause remains unresolved; changing completion
  timers or workspace scope would hide the symptom rather than address it.
- Loader caching, deferred gutter index refresh and the invalid formatter
  shortcut retain their previous rejection status. The Selene crash observation
  remains unresolved; this investigation did not repeat the unsafe large-save
  workload or claim it fixed.

### Durable evidence and cleanup

All raw journals (including the invalid first pilot), diagnostic drivers,
cross-over server state/logs, architectural survey reports, final source/test
snapshots and command output are preserved in:

`~/.local/state/poincare/benchmarks/20261024-optimization-evidence.tar.gz`

Archive SHA-256:
`7dc1e4a35fbbec7b5b44fed6de73df8512d813089ed50b25964cb168b7044075`.
The gzip integrity check passed, the tar index contained 4,592 entries and all
required journals/drivers/snapshots, and no process remained with a working
directory inside the experiment workspace. Archived raw journals, temporary
drivers and disposable projects/state were then removed from the live evidence
directory. Extract the archive to a scratch directory to replay raw journals;
the saved experiment drivers also document the modified acquisition policies.

The evidence directory keeps compact effect/full-suite summaries, verification
output, hypotheses, source-investigation reports and `archive.sha256`, alongside
the `baseline` and `equal-candidate` Nix GC roots. Existing repository artifacts,
prior evidence, unrelated jj changes and bookmark conflicts were left untouched.
