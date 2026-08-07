-- Minimal self-contained test runner.
local M = {}

local stats = { passed = 0, failed = 0, failures = {} }
local current_group = ""

function M.describe(name, fn)
  current_group = name
  fn()
  current_group = ""
end

function M.it(name, fn)
  local ok, err = pcall(fn)
  local full_name = (current_group ~= "" and (current_group .. " > ") or "") .. name
  if ok then
    stats.passed = stats.passed + 1
    print(string.format("  [PASS] %s", full_name))
  else
    stats.failed = stats.failed + 1
    stats.failures[#stats.failures + 1] = { name = full_name, err = err }
    print(string.format("  [FAIL] %s -- %s", full_name, tostring(err)))
  end
end

local function fmt(v)
  if type(v) == "table" then
    local parts = {}
    local n = #v
    if n > 0 then
      for i = 1, n do parts[#parts + 1] = fmt(v[i]) end
      return "{" .. table.concat(parts, ", ") .. "}"
    end
    for k, val in pairs(v) do
      parts[#parts + 1] = tostring(k) .. "=" .. fmt(val)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(v)
end

local function deep_eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deep_eq(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end
M.deep_eq = deep_eq

function M.eq(actual, expected, msg)
  if not deep_eq(actual, expected) then
    error(string.format("%sexpected %s, got %s",
      msg and (msg .. ": ") or "", fmt(expected), fmt(actual)), 2)
  end
end

function M.ok(value, msg)
  if not value then
    error(msg or "expected truthy value, got " .. fmt(value), 2)
  end
end

function M.not_ok(value, msg)
  if value then
    error(msg or "expected falsy value, got " .. fmt(value), 2)
  end
end

function M.near(actual, expected, tolerance, msg)
  tolerance = tolerance or 1e-9
  if math.abs(actual - expected) > tolerance then
    error(string.format("%sexpected %s within %s, got %s",
      msg and (msg .. ": ") or "", fmt(expected), fmt(tolerance), fmt(actual)), 2)
  end
end

function M.throws(fn, msg)
  local ok = pcall(fn)
  if ok then
    error(msg or "expected function to raise an error, but it did not", 2)
  end
end

function M.summary_and_exit()
  local total = stats.passed + stats.failed
  print(string.format("\n%d passed, %d failed, %d total", stats.passed, stats.failed, total))
  if stats.failed > 0 then
    os.exit(1)
  end
  os.exit(0)
end

function M.reset_stats()
  stats.passed, stats.failed, stats.failures = 0, 0, {}
end

M.stats = stats

return M
