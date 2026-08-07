-- Unit tests for the shared game controller.
local loader = dofile("loader.lua")()

local T = loader("tests/test_runner")
local board = loader("lib/board")
local session_mod = loader("lib/game_session")

local function state_for(board_value)
  return {
    board = board_value,
    score = 10,
    best = 20,
    moves_count = 3,
    elapsed_seconds = 5,
    palette = "ocean",
  }
end

T.describe("GameSession", function()
  T.it("moves, records history and restores the snapshot", function()
    local b = board.new_empty_board()
    b[1][1], b[1][2] = 2, 2
    local s = session_mod.new({
      state = state_for(b),
      clock = function() return 100 end,
      spawn_tile = function(target)
        target[4][4] = 2
        return { r = 4, c = 4, value = 2 }
      end,
    })
    local result = s:move("left")
    T.ok(result.changed)
    T.eq(s.score, 14)
    T.ok(s:can_undo())
    T.ok(s:undo())
    T.eq(s.board, b)
    T.eq(s.score, 10)
    T.eq(s.moves_count, 3)
  end)

  T.it("restart can be undone", function()
    local b = board.new_empty_board()
    b[2][2] = 8
    local s = session_mod.new({
      state = state_for(b),
      clock = function() return 10 end,
      spawn_tile = function(target)
        target[1][1] = 2
        return { r = 1, c = 1, value = 2 }
      end,
    })
    s:restart()
    T.ok(s:can_undo())
    T.ok(s:undo())
    T.eq(s.board, b)
    T.eq(s.palette, "ocean")
  end)

  T.it("pause freezes elapsed time", function()
    local now = 50
    local b = board.new_empty_board()
    b[1][1] = 2
    local s = session_mod.new({ state = state_for(b), clock = function() return now end })
    now = 53
    T.near(s:current_elapsed(), 8)
    s:set_paused(true)
    now = 100
    T.near(s:current_elapsed(), 8)
    s:set_paused(false)
    now = 102
    T.near(s:current_elapsed(), 10)
  end)

  T.it("palette is session-local", function()
    local b = board.new_empty_board()
    local s = session_mod.new({ state = state_for(b), clock = function() return 0 end })
    T.eq(s.palette, "ocean")
    T.eq(s:cycle_palette(), "classic")
    T.eq(s:snapshot().palette, "classic")
  end)
end)

T.summary_and_exit()
