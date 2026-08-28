local loader = dofile("loader.lua")()
local T = loader("tests/test_runner")

far = { Flags = {} }
bit64 = { bor = function(a, b) return a + b end }
local view = loader("far/dialog_view")

local function update_positions(score, best, board_w)
  local positions = {}
  local hdlg = {
    EnableRedraw = function() end,
    ShowItem = function() end,
    SetText = function() end,
    Enable = function() end,
    send = function(_, _, id, position) positions[id] = position end,
  }
  view.update(hdlg, { score_label = 1, score = 2, best_label = 3, best = 4,
      moves = 5, time = 6, palette = 7, pause_button = 8, status = 9,
      undo_button = 10 }, {
    doublebox_x1 = 0, doublebox_x2 = 30, doublebox_y1 = 0, doublebox_y2 = 10,
    board_w = board_w, board_x1 = 4, board_x2 = 3 + board_w, board_y2 = 9,
    stats_x1 = 20, stats_total_width = 10,
  }, {
    score = score, pending_score = 0, best = best, moves_count = 0,
    palette = "classic", paused = false,
    can_undo = function() return false end,
    has_pending_score = function() return false end,
    current_elapsed = function() return 0 end,
    status = "",
  }, false)
  return positions
end

T.describe("footer layout", function()
  T.it("keeps Best at the board edge when the footer fits", function()
    local p = update_positions(2, 4, 20)
    T.eq(p[3].Left, 15)
  end)

  T.it("moves Best to the frame edge when the footer does not fit", function()
    local p = update_positions(123, 456, 20)
    T.eq(p[3].Left, 18)
  end)
end)

T.summary_and_exit()
