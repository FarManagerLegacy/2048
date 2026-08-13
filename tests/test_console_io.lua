-- Unit tests for console rendering and platform key decoding.
-- Run with: luajit tests/test_console_io.lua

local loader = dofile("loader.lua")()

local T = loader("tests/test_runner")
local render = loader("console/render")
local tiles_mod = loader("lib/tiles")
local board = loader("lib/board")
local platform = loader("console/platform")
local ffi = require("ffi")

T.describe("console.platform", function()
  T.it("exposes the console facade without touching the terminal", function()
    for _, name in ipairs({
      "prepare_console", "restore_console", "sleep", "now", "kbhit",
      "flush_input", "read_byte", "read_key", "_decode_key",
    }) do
      T.eq(type(platform[name]), "function")
    end
    T.eq(platform.restore_console(), true)
  end)

  T.it("maps common game keys", function()
    local expected = {
      { " ", "pause" }, { "n", "restart" }, { "N", "restart" },
      { "<", "palette_prev" }, { ">", "palette_next" },
    }
    for _, item in ipairs(expected) do
      T.eq(platform._decode_key(string.byte(item[1]), function() end), item[2])
    end
    T.eq(platform._decode_key(0x1b, function() end), "quit")
    T.eq(platform._decode_key(string.byte("P"), function() end), nil)
  end)

  T.it("maps this platform's arrow byte sequences", function()
    if ffi.os == "Windows" then
      local codes = { [0x48] = "up", [0x50] = "down", [0x4b] = "left", [0x4d] = "right" }
      for code, direction in pairs(codes) do
        T.eq(platform._decode_key(0xe0, function() return code end), direction)
        T.eq(platform._decode_key(0x00, function() return code end), direction)
      end
    else
      local codes = { [0x41] = "up", [0x42] = "down", [0x43] = "right", [0x44] = "left" }
      for code, direction in pairs(codes) do
        for _, prefix in ipairs({ 0x5b, 0x4f }) do
          local bytes = { prefix, code }
          T.eq(platform._decode_key(0x1b, function() return table.remove(bytes, 1) end), direction)
        end
      end
      T.eq(platform._decode_key(0x1b, function() return 0x5b end), "quit")
    end
  end)
end)

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
  T.it("renders a pending score delta", function()
    --luacheck: ignore 122/io
    local captured, old_write = "", io.write
    io.write = function(value) captured = captured .. value end
    render.render_frame({
      tiles = {}, score = 10, score_delta = 4, best = 20,
      moves_count = 3, elapsed_seconds = 0,
    })
    io.write = old_write
    T.ok(captured:find("10 +4", 1, true) ~= nil)
  end)

  T.it("renders tile digits in bold", function()
    --luacheck: ignore 122/io
    local captured, old_write = "", io.write
    io.write = function(value) captured = captured .. value end
    render.render_frame({
      tiles = { { row = 0, col = 0, value = 1 } },
      score = 0, best = 0, moves_count = 0, elapsed_seconds = 0,
    })
    io.write = old_write
    T.ok(captured:find("\x1b[1m2", 1, true) ~= nil)
  end)

  T.it("does not add ANSI blink when the status effect disables it", function()
    --luacheck: ignore 122/io
    local captured = ""
    local old_write = io.write
    io.write = function(value) captured = captured .. value end
    render.render_frame({
      tiles = {}, score = 0, best = 0, moves_count = 0,
      elapsed_seconds = 0, status_text = "PAUSED", blink = false,
    })
    io.write = old_write
    T.not_ok(captured:find("\x1b[5m", 1, true))
  end)

  T.it("applies fade to the board background", function()
    --luacheck: ignore 122/io
    local captured = ""
    local old_write = io.write
    io.write = function(value) captured = captured .. value end
    render.render_frame({
      tiles = {}, score = 0, best = 0, moves_count = 0,
      elapsed_seconds = 0, fade = 0.55,
    })
    io.write = old_write
    T.ok(captured:find("\x1b[48;2;84;77;72m", 1, true) ~= nil)
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
