-- Unit tests for pure-logic Lua modules. Run with: luajit tests/test_core.lua
local loader = dofile("loader.lua")()
local temp = dofile("tests/test_helper.lua")

local T = loader("tests/test_runner")
local board = loader("lib/board")
local util = loader("lib/util")
local color = loader("lib/color")
local geometry = loader("lib/geometry")
local layout = loader("far/dialog_layout")
local save = loader("lib/save")

math.randomseed(12345)

T.describe("move mechanics", function()
  T.it("simple merge left", function()
    local b = board.new_empty_board()
    b[1][1], b[1][2] = 1, 1
    local new_b, _, score, changed = board.move_board(b, "left")
    T.ok(changed)
    T.eq(new_b[1][1], 2)
    T.eq(score, 4)
  end)

  T.it("no double merge in one move", function()
    local b = board.new_empty_board()
    b[1] = { 1, 1, 1, 1 }
    local new_b, _, score, _ = board.move_board(b, "left")
    T.eq(new_b[1], { 2, 2, 0, 0 })
    T.eq(score, 8)
  end)

  T.it("move without change reports unchanged", function()
    local b = board.new_empty_board()
    b[1] = { 1, 2, 3, 4 }
    local _, _, _, changed = board.move_board(b, "left")
    T.not_ok(changed)
  end)

  T.it("all four directions agree on symmetry", function()
    local b = board.new_empty_board()
    b[2][2] = 1
    b[2][3] = 1
    local new_b, _, score, changed = board.move_board(b, "right")
    T.ok(changed)
    T.eq(new_b[2][4], 2)
    T.eq(score, 4)
  end)

  T.it("uses the dimensions of a rectangular board", function()
    local b = {
      { 1, 0, 1, 0, 0 },
      { 0, 0, 0, 0, 0 },
      { 0, 0, 0, 0, 0 },
    }
    local new_b, _, score, changed = board.move_board(b, "right")
    T.ok(changed)
    T.eq(new_b, {
      { 0, 0, 0, 0, 2 },
      { 0, 0, 0, 0, 0 },
      { 0, 0, 0, 0, 0 },
    })
    T.eq(score, 4)
  end)
end)

T.describe("spawn outcomes", function()
  T.it("enumerates every spawn without changing the source board", function()
    local b = { { 0, 0 } }
    local outcomes = board.spawn_outcomes(b)
    local rank_one_probability, rank_two_probability = 0, 0
    T.eq(#outcomes, 4)
    T.eq(b, { { 0, 0 } })
    for _, outcome in ipairs(outcomes) do
      local changed_cells = 0
      for c = 1, 2 do if outcome.state[1][c] ~= 0 then changed_cells = changed_cells + 1 end end
      T.eq(changed_cells, 1)
      if outcome.state[1][1] == 1 or outcome.state[1][2] == 1 then
        rank_one_probability = rank_one_probability + outcome.probability
      else
        rank_two_probability = rank_two_probability + outcome.probability
      end
    end
    T.near(rank_one_probability, 0.9)
    T.near(rank_two_probability, 0.1)
  end)
end)

T.describe("end-state detection", function()
  T.it("reported stuck board is detected as game_over", function()
    local b = {
      { 1, 2, 5, 4 },
      { 3, 4, 6, 1 },
      { 4, 5, 7, 3 },
      { 2, 1, 3, 1 },
    }
    T.not_ok(board.any_move_possible(b))
    T.eq(board.compute_status(b), "game_over")
  end)

  T.it("board with empty cell is not game_over", function()
    local b = board.new_empty_board()
    b[1][1] = 1
    T.eq(board.compute_status(b), "")
  end)

  T.it("win takes priority over game_over check", function()
    local b = {
      { 11, 1, 2, 3 },
      { 4, 5, 6, 7 },
      { 8, 9, 1, 2 },
      { 3, 4, 5, 6 },
    }
    T.eq(board.compute_status(b), "won")
  end)
end)

T.describe("palette and color", function()
  T.it("cycle_palette wraps around", function()
    local start = "classic"
    local current = start
    local names = color._PALETTE_NAMES
    for _ = 1, #names do
      current = color.cycle_palette(current)
    end
    T.eq(current, start)
  end)

  T.it("classic palette matches original 2048 colors", function()
    T.eq(color.board_bg_color("classic"), { 187, 173, 160 })
    T.eq(color.empty_color("classic"), { 205, 193, 180 })
    T.eq(color.tile_text_color(1, "classic"), { 119, 110, 101 })
    T.eq(color.tile_text_color(2, "classic"), { 119, 110, 101 })
    T.eq(color.tile_text_color(3, "classic"), { 249, 246, 242 })
    T.eq(color.tile_color(1, "classic"), { 238, 228, 218 })
    T.eq(color.tile_color(11, "classic"), { 237, 194, 46 })
  end)

  T.it("tile_color extrapolates beyond defined values", function()
    local c4096 = color.tile_color(12, "classic")
    local c2048 = color.tile_color(11, "classic")
    T.ok(type(c4096) == "table")
    T.not_ok(T.deep_eq(c4096, c2048))
  end)
end)

T.describe("geometry", function()
  T.it("cell height matches the requested geometry unit", function()
    for unit = 1, 9 do
      local _, h = geometry.compute_cell_dimensions(unit, geometry.CHAR_ASPECT)
      T.eq(h, unit, "wrong height for unit=" .. unit)
    end
  end)

  T.it("current configured geometry", function()
    local w, h = geometry.compute_cell_dimensions(geometry.UNIT, geometry.CHAR_ASPECT)
    T.eq(geometry.CELL_W, w)
    T.eq(geometry.CELL_H, h)
  end)

  T.it("keeps the preferred unit and caps it to the dialog height", function()
    geometry.set_unit(2)
    local geom = layout.fit_to_height(32)
    T.eq(geom.unit, 2)
    T.eq(geometry.UNIT, geom.unit)
    T.ok(geom.dialog_h <= 32)

    geometry.set_unit(9)
    geom = layout.fit_to_height(32)
    T.eq(geom.unit, 6)
    T.ok(geom.dialog_h <= 32)
    geometry.set_unit(7)
    T.ok(layout.calculate().dialog_h > 32)
    geometry.set_unit(2)
    T.eq(geometry.GAP_Y, 1)
  end)
end)

T.describe("duration formatting", function()
  T.it("seconds only", function()
    T.eq(util.format_duration(5), "00:05")
  end)

  T.it("minutes and seconds", function()
    T.eq(util.format_duration(65), "01:05")
  end)

  T.it("hours minutes seconds", function()
    T.eq(util.format_duration(3725), "01:02:05")
  end)

  T.it("negative input clamped to zero", function()
    T.eq(util.format_duration(-5), "00:00")
  end)
end)

T.describe("save/load round trip", function()
  local orig_save_path
  local temp_dir

  local function setup_tmp_save_path()
    orig_save_path = save.SAVE_PATH
    temp_dir = temp.new_temp_dir("2048-save")
    save.SAVE_PATH = temp_dir.path .. package.config:sub(1, 1) .. "2048.save"
  end

  local function teardown_tmp_save_path()
    save.clear_save()
    save.SAVE_PATH = orig_save_path
    temp_dir.cleanup()
  end

  T.it("round trip preserves fields", function()
    setup_tmp_save_path()
    local b = board.new_empty_board()
    board.spawn_tile(b)
    board.spawn_tile(b)
    save.save_state({
      board = b, score = 120, best = 500, moves_count = 7,
      elapsed_seconds = 42.5, palette = "classic",
    })
    local loaded = save.load_state()
    T.eq(loaded.board, b)
    T.eq(loaded.score, 120)
    T.eq(loaded.best, 500)
    T.eq(loaded.moves_count, 7)
    T.eq(loaded.elapsed_seconds, 42.5)
    teardown_tmp_save_path()
  end)

  T.it("rejects saved rectangular geometry", function()
    setup_tmp_save_path()
    local b = {
      { 0, 0, 0, 0, 0 },
      { 0, 0, 0, 0, 0 },
      { 0, 0, 0, 0, 2 },
    }
    save.save_state({
      board = b,
      score = 0, best = 0, moves_count = 0,
      elapsed_seconds = 0, palette = "classic",
    })
    local loaded = save.load_state()
    T.eq(loaded, nil)
    teardown_tmp_save_path()
  end)

  T.it("clear_save removes file", function()
    setup_tmp_save_path()
    local b = board.new_empty_board()
    save.save_state({
      board = b, score = 0, best = 0, moves_count = 0,
      elapsed_seconds = 0, palette = "classic",
    })
    local function save_exists()
      local f = io.open(save.SAVE_PATH, "r")
      if f then f:close(); return true end
      return false
    end
    T.ok(save_exists())
    save.clear_save()
    T.not_ok(save_exists())
    teardown_tmp_save_path()
  end)

  T.it("load missing file returns nil", function()
    setup_tmp_save_path()
    save.clear_save()
    T.eq(save.load_state(), nil)
    teardown_tmp_save_path()
  end)

  T.it("load corrupted file returns nil", function()
    setup_tmp_save_path()
    local f = io.open(save.SAVE_PATH, "w")
    f:write("not valid json {{{")
    f:close()
    T.eq(save.load_state(), nil)
    teardown_tmp_save_path()
  end)

  T.it("rejects wrong game ids and non-integer indices", function()
    setup_tmp_save_path()
    local f = io.open(save.SAVE_PATH, "w")
    f:write('{game="other",board={{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0}}}')
    f:close()
    T.eq(save.load_state(), nil)
    f = io.open(save.SAVE_PATH, "w")
    f:write('{game="2048",board={{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,1.5}}}')
    f:close()
    T.eq(save.load_state(), nil)
    teardown_tmp_save_path()
  end)
end)

T.summary_and_exit()
