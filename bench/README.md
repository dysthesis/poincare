# Benchmark harness (P4)

Measures the wrapped Neovim from this flake. Zero flake coupling: scripts
consume `nix build` outputs and `bench/` fixtures only, so any two commits
can be A/B'd. All artefacts land in `bench/results/*.json` (gitignored;
schemas frozen for CI — see `TODO.md` Contracts).

## Dependencies

`nix` plus, for the startup scripts, `hyperfine`:

```sh
nix shell --inputs-from . nixpkgs#hyperfine
```

Statistics run as Lua under the built Neovim itself (`bench/stats.lua`) —
no python/jq needed. `lua-language-server` (devShell) enables the M4 probe;
without it the probe records a clean skip.

## Usage

```sh
bench/noise-floor.sh                  # B0 — ALWAYS FIRST; same binary as both arms
bench/startup.sh . "git+file:$PWD?rev=$(git rev-parse HEAD~1)"   # B1: M1, M2, M7
bench/deferred.sh                     # B2: M3, M4, M5, M8
bench/attribute.sh                    # single-run --startuptime triage (no stats)
```

Fixtures (`bench/files/`, gitignored) are generated deterministically by
`bench/files/gen.sh`; every script regenerates them on demand.

## Verdict rule (global, B0)

A difference is real iff the bootstrap 95% CI of the ratio of medians
excludes 1.0 **and** |Δmedian| exceeds the measured noise floor
(`results/noise-floor.json`). `startup.sh` refuses to run without that
artefact. Any "X is faster" claim in this repo cites both numbers.

## Knobs

| env               | default | meaning                                    |
| ----------------- | ------- | ------------------------------------------ |
| `BENCH_CPU`       | 3       | core to pin benchmarked processes to       |
| `BENCH_NO_TUNE`   | unset   | 1 = skip governor/turbo/SMT tuning         |
| `BENCH_COLD_PAGE` | unset   | 1 = add the page-cache-drop experiment     |
| `BENCH_*_RUNS`    | per id  | override run counts (NOISE/M1/M2/M3/M4/M5) |

Tuning needs passwordless sudo and restores prior state on exit; without it
the scripts run untuned — acceptable, because every verdict is gated on the
noise floor measured under the same conditions.

## Blind spots (by design)

- `UIEnter` never fires headless ⇒ `DeferredUIEnter` work costs zero in
  M1/M2. The deferred ledger (`deferred.sh`) owns that cost.
- The `write` scenario measures conform's load + dispatch, not the
  formatter binary (intentionally absent from the closure).
- `since_start_ms` in ledger output is relative to `--cmd` injection
  (pre-`init.lua`), not process exec.
