-- Greedy solver tests. Run with: luajit tests/test_ai.lua
local loader = dofile("loader.lua")()
local T = loader("tests/test_runner")
local board = loader("lib/board")
local directions = { "up", "down", "left", "right" }
local greedy = loader("lib/ai-greedy")

local function is_direction(value)
  for _, direction in ipairs(directions) do
    if value == direction then return true end
  end
  return false
end

T.describe("greedy solver", function()
  T.it("chooses a legal move", function()
    local b = board.new_empty_board()
    b[1][1], b[1][2] = 1, 1
    T.ok(is_direction(greedy.find_best_move(b, 2, 1000)))
  end)

  T.it("returns nil on a blocked board", function()
    local b = {
      { 1, 2, 3, 4 }, { 4, 3, 2, 1 },
      { 2, 1, 4, 3 }, { 3, 4, 1, 2 },
    }
    T.eq(greedy.find_best_move(b, 2, 1000), nil)
  end)

  T.it("supports a rectangular board", function()
    local b = { { 1, 1, 0 }, { 0, 2, 0 } }
    T.ok(is_direction(greedy.find_best_move(b, 2, 1000)))
  end)
end)

T.describe("greedy solver orientation", function()
  T.it("keeps equal maximum tiles rotation-invariant", function()
    local original = { { 3, 0, 0 }, { 0, 3, 0 }, { 0, 0, 0 } }
    local rotated = { { 0, 0, 0 }, { 0, 3, 0 }, { 0, 0, 3 } }
    T.eq(greedy._expected_spawn_score(original), greedy._expected_spawn_score(rotated))
  end)

  T.it("mirrors its choice after a 180-degree rotation", function()
    local original = {
      { 0, 0, 3, 0 }, { 0, 0, 9, 6 },
      { 4, 9, 1, 5 }, { 7, 1, 3, 8 },
    }
    local rotated = {
      { 8, 3, 1, 7 }, { 5, 1, 9, 4 },
      { 6, 9, 0, 0 }, { 0, 3, 0, 0 },
    }
    local opposite = { up = "down", down = "up", left = "right", right = "left" }
    T.eq(greedy.find_best_move(rotated), opposite[greedy.find_best_move(original)])
  end)
end)

T.describe("greedy solver spawn expectation", function()
  T.it("weights the next tile probabilities", function()
    T.ok(greedy._expected_spawn_score)
    T.eq(greedy._expected_spawn_score({ { 0, 0 } }), 111)
  end)

  T.it("uses the board spawn distribution", function()
    local saved = board.SPAWN_DISTRIBUTION
    board.SPAWN_DISTRIBUTION = { { value = 3, probability = 1 } }
    local score = greedy._expected_spawn_score({ { 0, 0 } })
    board.SPAWN_DISTRIBUTION = saved
    T.eq(score, 130)
  end)

  T.it("penalizes terminal spawns", function()
    T.ok(greedy._expected_spawn_score({ { 1, 2 }, { 3, 0 } }) < 0)
  end)
end)

T.summary_and_exit()
