-- bench/stats.lua — statistics helper for the benchmark harness (P4).
--
-- Runs under the built Neovim itself (`nvim -l bench/stats.lua <mode> ...`)
-- so the harness needs no python/R; the artefact under test doubles as the
-- interpreter. All randomness is a seeded LCG: identical inputs give
-- identical outputs.
--
-- Modes (all write a JSON artefact; schemas frozen for P6):
--   noise   <hyperfine.json> <store_path> <out.json>
--   verdict <hyperfine.json> <noise-floor.json> <out.json> <metric_id>
--           <experiment> <variant> <refA> <refB> <pathA> <pathB>
--   ledger  <scenario> <out.json> <run.json...>
--   tsparse <probe.json> <out.json>
--   m4      <out.json> <run.json...>
--   m7      <warm-result.json> <cold-result.json> <out.json>
--   rss     <out.json> <ledger-result.json...>
--
-- Verdict rule (B0, global for this repo): a difference is real iff the
-- bootstrap 95% CI of the ratio of medians excludes 1.0 AND the absolute
-- median delta exceeds the measured noise floor. No exceptions.

local BOOTSTRAP_ITERS = 5000

local function read_json(path)
  local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
  local text = f:read('*a')
  f:close()
  return vim.json.decode(text)
end

local function write_json(path, value)
  local f = assert(io.open(path, 'w'), 'cannot write ' .. path)
  f:write(vim.json.encode(value))
  f:write('\n')
  f:close()
end

local function sorted_copy(values)
  local copy = {}
  for i, v in ipairs(values) do
    copy[i] = v
  end
  table.sort(copy)
  return copy
end

-- Type-1 (inverse ECDF) quantile on a pre-sorted array.
local function quantile_sorted(sorted, q)
  local n = #sorted
  assert(n > 0, 'quantile of empty sample')
  local idx = math.ceil(q * n)
  if idx < 1 then
    idx = 1
  elseif idx > n then
    idx = n
  end
  return sorted[idx]
end

local function median(values)
  local sorted = sorted_copy(values)
  local n = #sorted
  if n % 2 == 1 then
    return sorted[(n + 1) / 2]
  end
  return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

local function iqr(values)
  local sorted = sorted_copy(values)
  return quantile_sorted(sorted, 0.75) - quantile_sorted(sorted, 0.25)
end

-- Deterministic LCG (glibc constants); good enough for bootstrap resampling.
local lcg_state = 42
local function lcg_index(n)
  lcg_state = (lcg_state * 1103515245 + 12345) % 2147483648
  return (lcg_state % n) + 1
end

local function resample_median(values)
  local n = #values
  local sample = {}
  for i = 1, n do
    sample[i] = values[lcg_index(n)]
  end
  return median(sample)
end

-- Bootstrap 95% CI for median(a)/median(b).
local function ratio_ci95(a, b)
  local ratios = {}
  for i = 1, BOOTSTRAP_ITERS do
    ratios[i] = resample_median(a) / resample_median(b)
  end
  local sorted = sorted_copy(ratios)
  return { quantile_sorted(sorted, 0.025), quantile_sorted(sorted, 0.975) }
end

local function arm_summary(result)
  return {
    command = result.command,
    median_ms = median(result.times) * 1000,
    iqr_ms = iqr(result.times) * 1000,
    runs = #result.times,
  }
end

-- Shared A/B summary of a two-arm hyperfine export (arm order = CLI order).
local function ab_summary(hyperfine_path)
  local data = read_json(hyperfine_path)
  assert(#data.results == 2, 'expected exactly two hyperfine arms')
  local a, b = data.results[1], data.results[2]
  local scale = 1000 -- hyperfine reports seconds; everything here is ms
  local times_a, times_b = a.times, b.times
  local median_a, median_b = median(times_a) * scale, median(times_b) * scale
  local ci = ratio_ci95(times_a, times_b)
  return {
    arms = { a = arm_summary(a), b = arm_summary(b) },
    ratio = median_a / median_b,
    ratio_ci95 = ci,
    delta_median_ms = median_a - median_b,
  }
end

local function now_utc()
  return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local modes = {}

function modes.noise(args)
  local hyperfine_path, store_path, out = args[1], args[2], args[3]
  local s = ab_summary(hyperfine_path)
  write_json(out, {
    schema = 'poincare-bench-v1',
    metric_id = 'noise-floor',
    unit = 'ms',
    store_path = store_path,
    arms = s.arms,
    ratio = s.ratio,
    ratio_ci95 = s.ratio_ci95,
    delta_median_abs_ms = math.abs(s.delta_median_ms),
    note = 'identical binary as both arms; any A/B verdict must beat this',
    generated_at = now_utc(),
  })
  print(
    string.format(
      'noise floor: |delta median| = %.3f ms, ratio %.4f, CI95 [%.4f, %.4f]',
      math.abs(s.delta_median_ms),
      s.ratio,
      s.ratio_ci95[1],
      s.ratio_ci95[2]
    )
  )
end

function modes.verdict(args)
  local hyperfine_path, noise_path, out = args[1], args[2], args[3]
  local metric_id, experiment, variant = args[4], args[5], args[6]
  local ref_a, ref_b, path_a, path_b = args[7], args[8], args[9], args[10]

  local s = ab_summary(hyperfine_path)
  local noise = read_json(noise_path)
  local floor = noise.delta_median_abs_ms

  local ci_excludes_one = s.ratio_ci95[1] > 1 or s.ratio_ci95[2] < 1
  local beats_floor = math.abs(s.delta_median_ms) > floor
  local verdict = 'indistinguishable'
  if ci_excludes_one and beats_floor then
    verdict = s.ratio < 1 and 'a_faster' or 'b_faster'
  end

  s.arms.a.flakeref, s.arms.a.store_path = ref_a, path_a
  s.arms.b.flakeref, s.arms.b.store_path = ref_b, path_b

  write_json(out, {
    schema = 'poincare-bench-v1',
    metric_id = metric_id,
    experiment = experiment,
    variant = variant,
    unit = 'ms',
    arms = s.arms,
    ratio = s.ratio,
    ratio_ci95 = s.ratio_ci95,
    delta_median_ms = s.delta_median_ms,
    noise_floor_ms = floor,
    ci_excludes_one = ci_excludes_one,
    beats_noise_floor = beats_floor,
    verdict = verdict,
    generated_at = now_utc(),
  })
  print(
    string.format(
      '%s %s/%s: A %.2f ms vs B %.2f ms, ratio %.4f CI95 [%.4f, %.4f], floor %.3f ms -> %s',
      metric_id,
      experiment,
      variant,
      s.arms.a.median_ms,
      s.arms.b.median_ms,
      s.ratio,
      s.ratio_ci95[1],
      s.ratio_ci95[2],
      floor,
      verdict
    )
  )
end

function modes.ledger(args)
  local scenario, out = args[1], args[2]
  local per_plugin, wall, rss_boot, rss_exit = {}, {}, {}, {}
  local runs = 0

  for i = 3, #args do
    local run = read_json(args[i])
    runs = runs + 1
    -- one sample per plugin per run: a plugin loads at most once per session
    local seen = {}
    for _, event in ipairs(run.events or {}) do
      local entry = per_plugin[event.name]
      if not entry then
        entry = { ms = {}, since = {}, depth_max = 0 }
        per_plugin[event.name] = entry
      end
      if not seen[event.name] then
        seen[event.name] = true
        entry.ms[#entry.ms + 1] = event.ms
        entry.since[#entry.since + 1] = event.since_start_ms
      end
      if event.depth > entry.depth_max then
        entry.depth_max = event.depth
      end
    end
    if run.scenario and run.scenario.ms then
      wall[#wall + 1] = run.scenario.ms
    end
    if run.rss_post_boot then
      rss_boot[#rss_boot + 1] = run.rss_post_boot
    end
    if run.rss_exit then
      rss_exit[#rss_exit + 1] = run.rss_exit
    end
  end

  local plugins = {}
  for name, entry in pairs(per_plugin) do
    plugins[#plugins + 1] = {
      name = name,
      median_ms = median(entry.ms),
      iqr_ms = iqr(entry.ms),
      median_since_start_ms = median(entry.since),
      depth_max = entry.depth_max,
      samples = #entry.ms,
    }
  end
  table.sort(plugins, function(x, y)
    return x.median_ms > y.median_ms
  end)

  write_json(out, {
    schema = 'poincare-bench-v1',
    metric_id = 'M3',
    scenario = scenario,
    unit = 'ms',
    runs = runs,
    note = 'nested loads (depth>0) are included in their parent event ms',
    plugins = plugins,
    scenario_wall = #wall > 0 and { median_ms = median(wall), iqr_ms = iqr(wall) } or nil,
    rss_bytes = {
      post_boot_median = #rss_boot > 0 and median(rss_boot) or nil,
      exit_median = #rss_exit > 0 and median(rss_exit) or nil,
    },
    generated_at = now_utc(),
  })
  print(string.format('M3 %s: %d runs, %d plugins', scenario, runs, #plugins))
end

function modes.tsparse(args)
  local probe_path, out = args[1], args[2]
  local probe = read_json(probe_path)
  local per_lang = {}
  local langs = 0
  for lang, samples in pairs(probe.per_lang or {}) do
    per_lang[lang] = {
      median_ns = median(samples),
      iqr_ns = iqr(samples),
      runs = #samples,
    }
    langs = langs + 1
  end
  write_json(out, {
    schema = 'poincare-bench-v1',
    metric_id = 'M5',
    unit = 'ns/parse',
    per_lang = per_lang,
    skipped = probe.skipped,
    generated_at = now_utc(),
  })
  print(string.format('M5: %d grammars measured', langs))
end

function modes.m4(args)
  local out = args[1]
  local samples, skipped = {}, nil
  for i = 2, #args do
    local run = read_json(args[i])
    if run.skipped then
      skipped = run.skipped
    elseif run.ms then
      samples[#samples + 1] = run.ms
    end
  end
  if #samples == 0 then
    write_json(out, {
      schema = 'poincare-bench-v1',
      metric_id = 'M4',
      unit = 'ms',
      skipped = skipped or 'no samples',
      generated_at = now_utc(),
    })
    print('M4: skipped (' .. (skipped or 'no samples') .. ')')
    return
  end
  write_json(out, {
    schema = 'poincare-bench-v1',
    metric_id = 'M4',
    unit = 'ms',
    server = 'lua-language-server',
    runs = #samples,
    median_ms = median(samples),
    iqr_ms = iqr(samples),
    generated_at = now_utc(),
  })
  print(string.format('M4: median %.1f ms over %d runs', median(samples), #samples))
end

function modes.m7(args)
  local warm = read_json(args[1])
  local cold = read_json(args[2])
  local out = args[3]
  local function delta(arm)
    return {
      warm_median_ms = warm.arms[arm].median_ms,
      cold_median_ms = cold.arms[arm].median_ms,
      delta_ms = cold.arms[arm].median_ms - warm.arms[arm].median_ms,
    }
  end
  write_json(out, {
    schema = 'poincare-bench-v1',
    metric_id = 'M7',
    unit = 'ms',
    note = 'cold-luac minus warm startup median, per arm (vim.loader benefit)',
    arms = { a = delta('a'), b = delta('b') },
    generated_at = now_utc(),
  })
  print(string.format('M7: vim.loader benefit A %.2f ms, B %.2f ms', delta('a').delta_ms, delta('b').delta_ms))
end

function modes.rss(args)
  local out = args[1]
  local scenarios = {}
  for i = 2, #args do
    local ledger = read_json(args[i])
    scenarios[ledger.scenario] = {
      post_boot_median_bytes = ledger.rss_bytes and ledger.rss_bytes.post_boot_median or nil,
      exit_median_bytes = ledger.rss_bytes and ledger.rss_bytes.exit_median or nil,
      runs = ledger.runs,
    }
  end
  write_json(out, {
    schema = 'poincare-bench-v1',
    metric_id = 'M8',
    unit = 'bytes',
    scenarios = scenarios,
    generated_at = now_utc(),
  })
  print('M8: RSS summary written')
end

local mode = arg[1]
if not mode or not modes[mode] then
  local names = {}
  for name in pairs(modes) do
    names[#names + 1] = name
  end
  table.sort(names)
  error('usage: nvim -l bench/stats.lua <' .. table.concat(names, '|') .. '> ...', 0)
end

local rest = {}
for i = 2, #arg do
  rest[#rest + 1] = arg[i]
end
modes[mode](rest)
