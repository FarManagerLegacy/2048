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

function M.update(hdlg, ids, geom, session, state)
  state = state or {}
  if not hdlg then return state end
  local text_changes = {}
  local function set_text(id, text)
    if state[id] ~= text then
      text_changes[#text_changes + 1] = { id, text }
      state[id] = text
    end
  end
  local width = geom.stats_label_width
  local score_text = string.format("%d", session.score)
  if session:has_pending_score() then
    score_text = score_text .. string.format(" &+%d", session.pending_score)
  end
  set_text(ids.score, make_stat_label("Score: ", width) .. score_text)
  set_text(ids.best, make_stat_label("Best: ", width) .. string.format("%d", session.best))
  set_text(ids.moves, make_stat_label("Moves: ", width) .. string.format("%d", session.moves_count))
  set_text(ids.time, make_stat_label("Time: ", width) .. util.format_duration(session:current_elapsed()))
  set_text(ids.palette, "Palette: " .. session.palette)
  set_text(ids.pause_button, session.paused and "Un&pause" or "&Pause")
  local undo_enabled = session:can_undo()
  local undo_changed = state.undo_enabled ~= undo_enabled
  state.undo_enabled = undo_enabled
  set_text(ids.status, session:has_pending_score() and "" or M.format_status(session.status))
  if #text_changes > 0 or undo_changed then
    hdlg:EnableRedraw(false)
    for _, change in ipairs(text_changes) do hdlg:SetText(change[1], change[2]) end
    if undo_changed then hdlg:Enable(ids.undo_button, undo_enabled) end
    hdlg:EnableRedraw(true)
  end
  return state
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
