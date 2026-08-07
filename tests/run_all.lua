-- Run every Lua test as a separate process.
local helper = dofile("tests/test_helper.lua")
local slash = package.config:sub(1, 1)
local windows = slash == "\\"
local bundle = "test_loader.generated.lua"
local unpacked = "test_loader.unpacked"

local function quote(path)
  return '"' .. path:gsub('"', '\\"') .. '"'
end

local function absolute_cwd()
  local pipe = assert(io.popen(windows and "cd" or "pwd", "r"))
  local path = pipe:read("*a"):gsub("[\r\n]+$", "")
  pipe:close()
  assert(path ~= "", "cannot determine source root")
  return path
end

local function run(command)
  local result = os.execute(command)
  return result == true or result == 0, result
end

local source_root = absolute_cwd()
local temp_dir = helper.new_temp_dir("2048-bundle")

local function in_temp(command)
  local cd = windows and "cd /d " or "cd "
  return run(cd .. quote(temp_dir.path) .. " && " .. command)
end

local function require_success(ok, result, message)
  if not ok then error(message .. " (exit " .. tostring(result) .. ")", 0) end
end

local function workflow()
  local source_loader = source_root .. slash .. "loader.lua"
  local source_entry = source_root .. slash .. "tests" .. slash .. "test_loader.lua"
  local source_debundle = source_root .. slash .. "debundle.lua"

  local ok, result = in_temp(
    "luajit " .. quote(source_loader) .. " " .. quote(source_entry) ..
    " " .. quote(bundle) .. " " .. quote(source_root))
  require_success(ok, result, "FAILED: bundle generation")

  ok, result = in_temp("luajit " .. quote(source_debundle) .. " " .. quote(bundle) .. " " .. quote(unpacked))
  require_success(ok, result, "FAILED: debundle generation")

  ok, result = in_temp("luajit " .. quote(unpacked .. slash .. "main.lua"))
  require_success(ok, result, "FAILED: debundled entrypoint")

  local tests = {
    "tests/test_loader.lua",
    bundle,
    "tests/test_core.lua",
    "tests/test_animation_fsm.lua",
    "tests/test_game_session.lua",
    "tests/test_tile_canvas.lua",
    "tests/test_console_io.lua",
    "tests/test_far_backend.lua",
  }
  for _, test in ipairs(tests) do
    print("\n== " .. test .. " ==")
    if test == bundle then
      ok, result = in_temp("luajit " .. quote(bundle))
    else
      ok, result = run("luajit " .. quote(test))
    end
    require_success(ok, result, "FAILED: " .. test)
  end
end

local ok, err = xpcall(workflow, function(message) return message end)
local cleaned, cleanup_error = pcall(temp_dir.cleanup)
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  os.exit(1)
end
if not cleaned then
  io.stderr:write("FAILED: temp cleanup: " .. tostring(cleanup_error) .. "\n")
  os.exit(1)
end
print("\nAll Lua tests passed.")
