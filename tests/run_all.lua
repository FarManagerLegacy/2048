-- Run every Lua test as a separate process.
-- Test files call os.exit(), so they cannot be combined with dofile().
local generated_bundle = "test_loader.generated.lua"
local unpacked_dir = "test_loader.unpacked"
local game_bundle = "test_2048.bundle.lua"
local game_bytecode = "test_2048.bundle.out"

local function run(command)
  local result = os.execute(command)
  return result == true or result == 0, result
end

local function remove_dir(path)
  if package.config:sub(1, 1) == "\\" then
    os.execute('rmdir /s /q "' .. path .. '" >nul 2>nul')
  else
    os.execute('rm -rf "' .. path .. '"')
  end
end

local function cleanup()
  os.remove(generated_bundle)
  os.remove(game_bundle)
  os.remove(game_bytecode)
  remove_dir(unpacked_dir)
end

cleanup()
local ok, result = run('luajit "loader.lua" "tests/test_loader.lua" "' .. generated_bundle .. '"')
if not ok then
  cleanup()
  io.stderr:write("FAILED: bundle generation\n")
  os.exit(result or 1)
end

ok, result = run('luajit "debundle.lua" "' .. generated_bundle .. '" "' .. unpacked_dir .. '"')
if not ok then
  cleanup()
  io.stderr:write("FAILED: debundle generation\n")
  os.exit(result or 1)
end
ok, result = run('luajit "' .. unpacked_dir .. '/main.lua"')
if not ok then
  cleanup()
  io.stderr:write("FAILED: debundled entrypoint\n")
  os.exit(result or 1)
end

ok, result = run('luajit "loader.lua" "main.lua" "' .. game_bundle .. '"')
if not ok then
  cleanup()
  io.stderr:write("FAILED: full bundle generation\n")
  os.exit(result or 1)
end
ok, result = run('luajit -b "' .. game_bundle .. '" "' .. game_bytecode .. '"')
if not ok then
  cleanup()
  io.stderr:write("FAILED: full bundle compilation\n")
  os.exit(result or 1)
end

local tests = {
  "tests/test_loader.lua",
  generated_bundle,
  "tests/test_core.lua",
  "tests/test_animation_fsm.lua",
  "tests/test_game_session.lua",
  "tests/test_tile_canvas.lua",
  "tests/test_status_effect.lua",
  "tests/test_console_io.lua",
  "tests/test_far_backend.lua",
  "tests/test_far_timer.lua",
}

for _, test in ipairs(tests) do
  print("\n== " .. test .. " ==")
  ok, result = run('luajit "' .. test .. '"')
  if not ok then
    cleanup()
    io.stderr:write("FAILED: " .. test .. "\n")
    os.exit(result or 1)
  end
end

cleanup()
print("\nAll Lua tests passed.")
