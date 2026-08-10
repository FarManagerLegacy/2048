-- Unit tests for animation_fsm.lua (pure state machines, no FAR/FFI
-- dependency -- fully testable with plain luajit). Run with:
--   luajit tests/test_animation_fsm.lua

local loader = dofile("loader.lua")()

local T = loader("tests/test_runner")
local board = loader("lib/board")
local constants = loader("lib/constants")
-- Fixture config: these tests cover this explicit baseline, not defaults.
constants.GEOMETRY_UNIT = 3
constants.USE_HALF_BLOCKS = true
local fsm = loader("lib/animation_fsm")
local geometry = loader("lib/geometry")

T.describe("animation easing", function()
  T.it("starts at 0 and ends at 1", function()
    T.near(fsm.ease_out_cubic(0), 0.0)
    T.near(fsm.ease_out_cubic(1), 1.0)
  end)

  T.it("is monotonically increasing over a sample of steps", function()
    local prev = -1
    for i = 0, 10 do
      local value = fsm.ease_out_cubic(i / 10)
      T.ok(value >= prev, "expected non-decreasing ease curve")
      prev = value
    end
  end)

  T.it("uses the configured easing power", function()
    local old_power = constants.ANIM_EASE_POWER
    constants.ANIM_EASE_POWER = 1
    local s = fsm.new_slide({ { fr = 1, fc = 1, tr = 1, tc = 2, value = 2 } })
    s:advance(1)
    local col = s:tiles()[1].col
    constants.ANIM_EASE_POWER = old_power
    T.near(col, 1 / s.total_steps, 1e-6)
  end)
end)

T.describe("adaptive frame pacing", function()
  T.it("divides the remaining wall-clock budget after rendering", function()
    T.near(fsm.next_frame_delay(1.0, 0.4, 3, 0.05), 0.2, 1e-6)
    T.eq(fsm.next_frame_delay(1.0, 1.1, 3), 0)
    T.eq(fsm.next_frame_delay(1.0, 0.4, 0), 0)
  end)
end)

T.describe("SlideFSM", function()
  T.it("an empty move list is immediately done", function()
    local s = fsm.new_slide({})
    T.ok(s:is_done())
    T.eq(#s:tiles(), 0)
  end)

  T.it("advances toward the target over total_steps frames", function()
    local moves = { { fr = 1, fc = 1, tr = 1, tc = 2, value = 2, merged = false } }
    local s = fsm.new_slide(moves)
    T.not_ok(s:is_done())
    s:advance(s.total_steps)
    T.ok(s:is_done())
    local tiles = s:tiles()
    T.eq(#tiles, 1)
    T.near(tiles[1].col, 1.0, 1e-6) -- fully arrived at column index 1 (0-based)
  end)

  T.it("advance() is clamped at total_steps, does not overshoot", function()
    local moves = { { fr = 1, fc = 1, tr = 1, tc = 2, value = 2, merged = false } }
    local s = fsm.new_slide(moves)
    s:advance(999)
    T.ok(s:is_done())
    T.eq(s.step, s.total_steps)
  end)

  T.it("partial advance is not yet done", function()
    local moves = { { fr = 1, fc = 1, tr = 1, tc = 2, value = 2, merged = false } }
    local s = fsm.new_slide(moves)
    s:advance(1)
    T.not_ok(s:is_done())
  end)

  T.it("keeps horizontal slides on the cubic seven-frame curve", function()
    local s = fsm.new_slide({ { fr = 1, fc = 1, tr = 1, tc = 2, value = 2 } })
    T.eq(s.total_steps, geometry.CELL_W + geometry.GAP_X > 0 and 5 or 0)
    s:advance(1)
    T.near(s:tiles()[1].col, fsm.ease_out_cubic(1 / s.total_steps), 1e-6)
  end)

  local function assert_vertical_half_steps(fr, tr, total_steps)
    local s = fsm.new_slide({ { fr = fr, fc = 1, tr = tr, tc = 1, value = 2 } })
    local start_half = (fr - 1) * geometry.ROW_STRIDE_Y * 2
    local direction = tr > fr and 1 or -1
    T.eq(s.total_steps, total_steps)
    for step = 1, total_steps do
      s:advance(1)
      local eased_step = math.abs(tr - fr) * geometry.ROW_STRIDE_Y * 2
        * fsm.ease_out_cubic(step / total_steps)
      T.near(s:tiles()[1].row * geometry.ROW_STRIDE_Y * 2, start_half + direction * eased_step, 1e-6)
    end
  end

  T.it("uses the same easing for vertical slides", function()
    assert_vertical_half_steps(1, 2, 5)
    assert_vertical_half_steps(1, 3, 10)
    assert_vertical_half_steps(4, 1, 15)
  end)

  T.it("uses whole-row vertical steps when half blocks are disabled", function()
    local old_use_half_blocks = constants.USE_HALF_BLOCKS
    constants.USE_HALF_BLOCKS = false
    local s = fsm.new_slide({ { fr = 1, fc = 1, tr = 2, tc = 1, value = 2 } })
    constants.USE_HALF_BLOCKS = old_use_half_blocks
    T.eq(s.total_steps, geometry.ROW_STRIDE_Y)
    s:advance(1)
    T.near(s:tiles()[1].row, fsm.ease_out_cubic(1 / geometry.ROW_STRIDE_Y), 1e-6)
  end)
end)

T.describe("MergePopFSM", function()
  T.it("no merges means immediately done", function()
    local b = board.new_empty_board()
    b[1][1] = 2
    local mp = fsm.new_merge_pop(b, {})
    T.ok(mp:is_done())
  end)

  T.it("tracks a merge target and produces a tile with bg/fg override", function()
    local b = board.new_empty_board()
    b[1][1] = 4 -- post-merge value
    local moves = {
      { fr = 1, fc = 1, tr = 1, tc = 1, value = 2, merged = false },
      { fr = 1, fc = 2, tr = 1, tc = 1, value = 2, merged = true },
    }
    local mp = fsm.new_merge_pop(b, moves)
    T.not_ok(mp:is_done())
    mp:advance(constants.MERGE_POP_FRAMES)
    T.ok(mp:is_done())
    local tiles = mp:tiles()
    T.eq(#tiles, 1)
    T.eq(tiles[1].value, 4)
    T.ok(tiles[1].bg ~= nil)
    T.ok(tiles[1].fg ~= nil)
  end)

  T.it("static (non-merged) tiles pass through unchanged", function()
    local b = board.new_empty_board()
    b[1][1] = 4
    b[2][2] = 8 -- untouched by the merge
    local moves = {
      { fr = 1, fc = 1, tr = 1, tc = 1, value = 2, merged = false },
      { fr = 1, fc = 2, tr = 1, tc = 1, value = 2, merged = true },
    }
    local mp = fsm.new_merge_pop(b, moves)
    local tiles = mp:tiles()
    local found_static = false
    for _, t in ipairs(tiles) do
      if t.row == 1 and t.col == 1 and t.value == 8 and t.bg == nil then
        found_static = true
      end
    end
    T.ok(found_static, "expected the untouched 8-tile to appear without bg/fg override")
  end)
end)

T.describe("SpawnFadeFSM", function()
  T.it("fades the spawned tile's alpha from 0 to 1 over total_steps", function()
    local b = board.new_empty_board()
    b[1][1] = 2 -- the "spawned" tile
    local spawned = { r = 1, c = 1, value = 2 }
    local sf = fsm.new_spawn_fade(b, spawned)
    T.not_ok(sf:is_done())

    local function find_spawned_tile(tiles)
      for _, t in ipairs(tiles) do
        if t.row == 0 and t.col == 0 then return t end
      end
      return nil
    end

    -- Freshly created: zero progress -> the spawned tile is fully
    -- transparent (alpha 0). This matters because far/main.lua may call
    -- tiles() to draw the very first frame BEFORE any timer tick has
    -- fired (e.g. immediately after begin_move()), so step=0 must be a
    -- valid, renderable state -- not an off-by-one placeholder.
    local tile0 = find_spawned_tile(sf:tiles())
    T.ok(tile0 ~= nil, "expected the spawned tile to be present even at step=0")
    T.near(tile0.alpha, 0.0, 1e-6)

    sf:advance(1)
    local tile1 = find_spawned_tile(sf:tiles())
    T.near(tile1.alpha, 1 / constants.SPAWN_FADE_FRAMES, 1e-6)

    sf:advance(constants.SPAWN_FADE_FRAMES) -- drain remaining frames
    T.ok(sf:is_done())
    local tile_final = find_spawned_tile(sf:tiles())
    T.near(tile_final.alpha, 1.0, 1e-6)
  end)

  T.it("other board tiles have no alpha override", function()
    local b = board.new_empty_board()
    b[1][1] = 2
    b[3][3] = 16
    local spawned = { r = 1, c = 1, value = 2 }
    local sf = fsm.new_spawn_fade(b, spawned)
    local tiles = sf:tiles()
    local other
    for _, t in ipairs(tiles) do
      if t.row == 2 and t.col == 2 then other = t end
    end
    T.ok(other ~= nil)
    T.eq(other.alpha, nil)
  end)
end)

T.describe("MoveAnimation sequencing", function()
  T.it("chains slide -> merge_pop when there is no spawn", function()
    local pre_board = board.new_empty_board()
    pre_board[1][1], pre_board[1][2] = 2, 2
    local new_b, moves, _, changed = board.move_board(pre_board, "left")
    T.ok(changed)

    local anim = fsm.new_move_animation(new_b, moves, new_b, nil)
    T.not_ok(anim:is_done())

    anim:advance(anim.phases[1].total_steps)
    T.not_ok(anim:is_done())

    anim:advance(constants.MERGE_POP_FRAMES)
    T.ok(anim:is_done())
  end)

  T.it("chains slide -> merge_pop -> spawn_fade when a tile spawns", function()
    local pre_board = board.new_empty_board()
    pre_board[1][1], pre_board[1][2] = 2, 2
    local new_b, moves, _, changed = board.move_board(pre_board, "left")
    T.ok(changed)

    local spawned_board = board.copy_board(new_b)
    local spawned = board.spawn_tile(spawned_board)
    T.ok(spawned ~= nil)

    local anim = fsm.new_move_animation(new_b, moves, spawned_board, spawned)
    anim:advance(anim.phases[1].total_steps)
    anim:advance(constants.MERGE_POP_FRAMES)
    T.not_ok(anim:is_done())
    anim:advance(constants.SPAWN_FADE_FRAMES)
    T.ok(anim:is_done())
  end)

  T.it("skips merge_pop immediately if there was no merge, still not done till slide finishes", function()
    local pre_board = board.new_empty_board()
    pre_board[1][1] = 2
    pre_board[1][3] = 4
    local new_b, moves, _, changed = board.move_board(pre_board, "left")
    T.ok(changed)
    local anim = fsm.new_move_animation(new_b, moves, new_b, nil)
    T.not_ok(anim:is_done())
  end)

  T.it("advance() respects FRAMES_PER_TICK-sized steps without skipping phases", function()
    local pre_board = board.new_empty_board()
    pre_board[1][1], pre_board[1][2] = 2, 2
    local new_b, moves, _, _ = board.move_board(pre_board, "left")
    local anim = fsm.new_move_animation(new_b, moves, new_b, nil)
    local total_advances = 0
    while not anim:is_done() and total_advances < 1000 do
      anim:advance(1)
      total_advances = total_advances + 1
    end
    T.ok(anim:is_done())
    T.eq(total_advances, anim.phases[1].total_steps + constants.MERGE_POP_FRAMES)
  end)
end)

T.summary_and_exit()
