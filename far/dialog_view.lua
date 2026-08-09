-- FAR dialog text and status presentation.
local util = loader("lib/util")

local M = {}

local function make_stat_label(label, width)
  return label .. string.rep(" ", math.max(0, width - #label))
end

function M.format_status(status)
  if status == "won" then return "Won" end
  if status == "game_over" then return "Game over" end
  return ""
end

function M.update(far, hdlg, ids, geom, session, request_redraw)
  if not hdlg then return end
  local width = geom.stats_label_width
  local score_text = string.format("%d", session.score)
  if session:has_pending_score() then
    score_text = score_text .. string.format(" +%d", session.pending_score)
  end
  far.SendDlgMessage(hdlg, "DM_SETTEXTPTR", ids.score,
    make_stat_label("Score: ", width) .. score_text)
  far.SendDlgMessage(hdlg, "DM_SETTEXTPTR", ids.best,
    make_stat_label("Best: ", width) .. string.format("%d", session.best))
  far.SendDlgMessage(hdlg, "DM_SETTEXTPTR", ids.moves,
    make_stat_label("Moves: ", width) .. string.format("%d", session.moves_count))
  far.SendDlgMessage(hdlg, "DM_SETTEXTPTR", ids.time,
    make_stat_label("Time: ", width) .. util.format_duration(session:current_elapsed()))
  far.SendDlgMessage(hdlg, "DM_SETTEXTPTR", ids.palette, "Palette: " .. session.palette)
  far.SendDlgMessage(hdlg, "DM_SETTEXTPTR", ids.pause_button,
    session.paused and "Un&pause" or "&Pause")
  far.SendDlgMessage(hdlg, "DM_ENABLE", ids.undo_button, session:can_undo())
  far.SendDlgMessage(hdlg, "DM_SETTEXTPTR", ids.status,
    session:has_pending_score() and "" or M.format_status(session.status))
  if request_redraw then request_redraw() end
end

function M.apply_status_colors(F, bor, status, colors)
  local base_flags = colors[1].Flags
  if status == "game_over" then
    colors[1].ForegroundColor = 4
    colors[1].Flags = bor(base_flags, F.FCF_FG_INDEX, F.FCF_FG_BLINK)
  elseif status == "won" then
    colors[1].ForegroundColor = 2
    colors[1].Flags = bor(base_flags, F.FCF_FG_INDEX, F.FCF_FG_BLINK)
  else
    colors[1].Flags = base_flags
  end
  return colors
end

return M
