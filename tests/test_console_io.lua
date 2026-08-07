-- Unit tests for the platform-independent pieces of the I/O layer
-- (render.lua, animation.lua's pure math). winapi.lua is stubbed via
-- package.preload since it requires real Windows FFI.
-- Run with: luajit tests/test_console_io.lua

local loader = dofile("loader.lua")()

local fake_now = 0.0
package.preload["console.winapi"] = function()
  return {
    enable_windows_ansi = function() end,
    sleep = function(_) fake_now = fake_now + 0.001 end,
    now = function() return fake_now end,
    kbhit = function() return false end,
    read_key = function() return nil end,
    flush_input = function() end,
    _getch_byte = function() return string.byte("q") end,
  }
end

local T = loader("tests/test_runner")
local render = loader("console/render")
local tiles_mod = loader("lib/tiles")
local board = loader("lib/board")

T.describe("render: board_to_tiles", function()
  T.it("converts 1-based board to 0-based tile list", function()
    local b = board.new_empty_board()
    b[1][1] = 2
    b[4][4] = 4
    local tiles = tiles_mod.board_to_tiles(b)
    T.eq(#tiles, 2)
    local found_first, found_last = false, false
    for _, t in ipairs(tiles) do
      if t.row == 0 and t.col == 0 and t.value == 2 then found_first = true end
      if t.row == 3 and t.col == 3 and t.value == 4 then found_last = true end
    end
    T.ok(found_first, "expected a tile at 0,0 with value 2")
    T.ok(found_last, "expected a tile at 3,3 with value 4")
  end)

  T.it("skips empty cells", function()
    local b = board.new_empty_board()
    local tiles = tiles_mod.board_to_tiles(b)
    T.eq(#tiles, 0)
  end)
end)

T.describe("render: render_frame smoke test (stubbed winapi)", function()
  T.it("does not error for a simple board", function()
    local b = board.new_empty_board()
    b[1][1] = 2
    local ok, err = pcall(function()
      render.render_frame({
        tiles = tiles_mod.board_to_tiles(b), score = 4, best = 4,
        moves_count = 1, elapsed_seconds = 5, status_text = "",
      })
    end)
    T.ok(ok, err)
  end)

  T.it("does not error with a status message and paused flag set", function()
    local b = board.new_empty_board()
    b[1][1] = 2
    local ok, err = pcall(function()
      render.render_frame({
        tiles = tiles_mod.board_to_tiles(b), score = 4, best = 4,
        moves_count = 1, elapsed_seconds = 5, status_text = "GAME OVER",
        status_color = { 255, 90, 90 }, paused = true, blink_on = true,
      })
    end)
    T.ok(ok, err)
  end)

  T.it("keeps the board background behind sparkles", function()
    --luacheck: ignore 122/io
    local captured = ""
    local old_write = io.write
    io.write = function(value) captured = captured .. value end
    local ok, err = pcall(function()
      render.render_frame({
        tiles = {}, score = 0, best = 0, moves_count = 0,
        elapsed_seconds = 0, sparkles = {
          { rc = { 0, 0 }, color = { 255, 255, 255 }, ch = "*" },
        },
      })
    end)
    io.write = old_write
    T.ok(ok, err)
    T.ok(captured:find(
      "\x1b[48;2;205;193;180m\x1b[38;2;255;255;255m*", 1, true) ~= nil,
      "expected sparkle to retain the board background")
  end)
end)

T.summary_and_exit()
