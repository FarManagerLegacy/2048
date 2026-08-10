-- FAR dialog text and status presentation.
local util = loader("lib/util")
local F = far.Flags

local M = {}

local function make_stat_label(label, width)
  return label .. string.rep(" ", math.max(0, width - #label))
end

function M.format_status(status)
  if status == "won" then return "Won" end
  if status == "game_over" then return "Game over" end
  return ""
end

function M.update(hdlg, ids, geom, session)
  if not hdlg then return end
  local width = geom.stats_label_width
  local score_text = string.format("%d", session.score)
  if session:has_pending_score() then
    score_text = score_text .. string.format(" &+%d", session.pending_score)
  end
  hdlg:SetText(ids.score,
    make_stat_label("Score: ", width) .. score_text)
  hdlg:SetText(ids.best,
    make_stat_label("Best: ", width) .. string.format("%d", session.best))
  hdlg:SetText(ids.moves,
    make_stat_label("Moves: ", width) .. string.format("%d", session.moves_count))
  hdlg:SetText(ids.time,
    make_stat_label("Time: ", width) .. util.format_duration(session:current_elapsed()))
  hdlg:SetText(ids.palette, "Palette: " .. session.palette)
  hdlg:SetText(ids.pause_button,
    session.paused and "Un&pause" or "&Pause")
  hdlg:Enable(ids.undo_button, session:can_undo())
  hdlg:SetText(ids.status,
    session:has_pending_score() and "" or M.format_status(session.status))
end

function M.apply_status_colors(bor, status, colors)
  local base_flags = colors[1].Flags
  if status == "game_over" then
    colors[1].ForegroundColor = 4
  elseif status == "won" then
    colors[1].ForegroundColor = 2
  else
    return
  end
  colors[1].Flags = bor(base_flags, F.FCF_FG_INDEX, F.FCF_FG_BLINK)
  return colors
end

return M
