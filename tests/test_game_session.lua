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
    b[1][1], b[1][2] = 1, 1
    local s = session_mod.new({
      state = state_for(b),
      clock = function() return 100 end,
      spawn_tile = function(target)
        target[4][4] = 1
        return { r = 4, c = 4, value = 1 }
      end,
    })
    local result = s:move("left")
    T.ok(result.changed)
    T.eq(s.score, 10)
    T.eq(s.pending_score, 4)
    T.not_ok(s:move("right").changed)
    T.not_ok(s:undo())
    T.not_ok(s:restart())
    T.eq(s:settle_score(), 4)
    T.eq(s.score, 14)
    T.eq(s:settle_score(), 0)
    T.ok(s:can_undo())
    T.ok(s:undo())
    T.eq(s.board, b)
    T.eq(s.score, 10)
    T.eq(s.moves_count, 3)
  end)

  T.it("settles no-merge moves without blocking later moves", function()
    local b = board.new_empty_board()
    b[1][1] = 1
    local s = session_mod.new({
      state = state_for(b),
      clock = function() return 0 end,
      spawn_tile = function(target)
        target[4][4] = 1
        return { r = 4, c = 4, value = 1 }
      end,
    })
    local result = s:move("right")
    T.ok(result.changed)
    T.eq(s.pending_score, 0)
    T.eq(s.score, 10)
    T.eq(s:settle_score(), 0)
    T.eq(s.score, 10)
    local next_result = s:move("left")
    T.ok(next_result.changed)
    T.not_ok(s:has_pending_score())
  end)

  T.it("restart can be undone", function()
    local b = board.new_empty_board()
    b[2][2] = 3
    local s = session_mod.new({
      state = state_for(b),
      clock = function() return 10 end,
      spawn_tile = function(target)
        target[1][1] = 1
        return { r = 1, c = 1, value = 1 }
      end,
    })
    s:restart()
    T.ok(s:can_undo())
    T.ok(s:undo())
    T.eq(s.board, b)
    T.eq(s.palette, "ocean")
  end)

  T.it("keeps a merge score pending until the animation settles", function()
    local b = board.new_empty_board()
    b[1][1], b[1][2] = 1, 1
    local s = session_mod.new({
      state = state_for(b),
      clock = function() return 0 end,
      spawn_tile = function(target)
        target[4][4] = 1
        return { r = 4, c = 4, value = 1 }
      end,
    })

    T.ok(s:move("left").changed)
    T.ok(s:has_pending_score())
    T.eq(s:snapshot().score, 10)
    T.not_ok(s:restart())
    T.not_ok(s:undo())
    T.eq(s:settle_score(), 4)
    T.eq(s.score, 14)
    T.eq(s:settle_score(), 0)
  end)

  T.it("keeps best fixed during a game and promotes it on restart", function()
    local b = board.new_empty_board()
    b[1][1], b[1][2] = 1, 1
    local state = state_for(b)
    state.score, state.best = 20, 20
    local s = session_mod.new({
      state = state,
      clock = function() return 0 end,
      spawn_tile = function(target)
        target[4][4] = 1
        return { r = 4, c = 4, value = 1 }
      end,
    })
    s:move("left")
    s:settle_score()
    T.eq(s.score, 24)
    T.eq(s.best, 20)
    T.eq(s:snapshot().best, 24)
    s:restart()
    T.eq(s.best, 24)
  end)

  T.it("pause freezes elapsed time", function()
    local now = 50
    local b = board.new_empty_board()
    b[1][1] = 1
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

  T.it("restores the saved palette in its snapshot", function()
    local s = session_mod.new({
      state = state_for(board.new_empty_board()),
      clock = function() return 0 end,
    })
    T.eq(s.palette, "ocean")
    T.eq(s:snapshot().palette, "ocean")
  end)

  T.it("keeps palette changes isolated between sessions", function()
    local first = session_mod.new({
      state = state_for(board.new_empty_board()),
      clock = function() return 0 end,
    })
    local second_state = state_for(board.new_empty_board())
    second_state.palette = "classic"
    local second = session_mod.new({ state = second_state, clock = function() return 0 end })

    local first_palette = first:cycle_palette()
    T.not_ok(first_palette == "ocean")
    T.eq(first.palette, first_palette)
    T.eq(first:snapshot().palette, first_palette)
    T.eq(second.palette, "classic")
    T.eq(second:snapshot().palette, "classic")
  end)

end)

T.summary_and_exit()
