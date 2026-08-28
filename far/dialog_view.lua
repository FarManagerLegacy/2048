-- FAR dialog text and status presentation.
local util = loader("lib/util")
local config = loader("far/config")
local F = far.Flags
local bor = bit64.bor

local M = {}

local function footer_label(name, value)
  return config.FOOTER_LEFT_BORDER .. name .. ": " .. string.rep(" ", #value) ..
    config.FOOTER_RIGHT_BORDER
end

local function fit_item(hdlg, id, x, y, width)
  if hdlg.send then
    hdlg:send("DM_SETITEMPOSITION", id, {
      Left = x, Top = y, Right = x + width - 1, Bottom = y,
    })
  end
end

function M.format_status(status)
  if status == "won" then return "Won" end
  if status == "game_over" then return "Game over" end
  return ""
end

function M.update(hdlg, ids, geom, session, auto_play, state)
  state = state or {}
  if not hdlg then return state end
  local text_changes = {}
  local function set_text(id, text)
    if state[id] ~= text then
      text_changes[#text_changes + 1] = { id, text }
      state[id] = text
    end
  end
  local score_value = string.format("%d", session.score + session.pending_score)
  local score_visible = score_value ~= "0"
  set_text(ids.score_label, footer_label("Score", score_value))
  set_text(ids.score, score_value)
  local best_value = string.format("%d", session.best)
  local best_visible = best_value ~= "0"
  set_text(ids.best_label, footer_label("Best", best_value))
  set_text(ids.best, best_value)
  set_text(ids.moves, string.format("%d", session.moves_count))
  local time_value = " " .. util.format_duration(session:current_elapsed())
  set_text(ids.time, time_value)
  local palette_value = session.palette
  set_text(ids.palette, palette_value)
  set_text(ids.pause_button, (session.paused and " " or " &")..config.PLAY_GLYPH.." ")
  if ids.auto_button then
    set_text(ids.auto_button, auto_play and "&Auto Stop" or "&Auto Play")
  end
  local undo_enabled = session:can_undo()
  local undo_changed = state.undo_enabled ~= undo_enabled
  state.undo_enabled = undo_enabled
  set_text(ids.status, session:has_pending_score() and "" or M.format_status(session.status))
  local score_visibility_changed = state.score_visible ~= score_visible
  state.score_visible = score_visible
  local best_visibility_changed = state.best_visible ~= best_visible
  state.best_visible = best_visible
  local footer_key = table.concat({
    score_visible and score_value or "", best_visible and best_value or "",
  }, "\0")
  local footer_changed = state.footer_key ~= footer_key
  state.footer_key = footer_key
  local palette_changed = state.palette_value ~= session.palette
  state.palette_value = session.palette
  if #text_changes > 0 or undo_changed or score_visibility_changed or
      best_visibility_changed or footer_changed or palette_changed then
    hdlg:EnableRedraw(false)
    if score_visibility_changed then hdlg:ShowItem(ids.score, score_visible) end
    if score_visibility_changed then
      hdlg:ShowItem(ids.score_label, score_visible)
    end
    if best_visibility_changed then
      hdlg:ShowItem(ids.best, best_visible)
      hdlg:ShowItem(ids.best_label, best_visible)
    end
    if footer_changed then
      local y = geom.doublebox_y2
      local score_width = score_visible and #score_value + 9 or 0
      local best_width = best_visible and #best_value + 8 or 0
      if score_visible then
        local score_x = geom.doublebox_x1 + 2
        fit_item(hdlg, ids.score_label, score_x, y, score_width)
        fit_item(hdlg, ids.score, score_x + 8, y, #score_value)
      end
      if best_visible then
        local best_right = geom.board_x2
        if score_visible and score_width + best_width + 1 > geom.board_w then
          best_right = geom.doublebox_x2 - 2
        end
        local best_x = best_right - best_width + 1
        fit_item(hdlg, ids.best_label, best_x, y, best_width)
        fit_item(hdlg, ids.best, best_x + 7, y, #best_value)
      end
    end
    fit_item(hdlg, ids.time, geom.doublebox_x2 - 4 - #time_value, geom.doublebox_y1, #time_value)
    if palette_changed then
      local palette_width = #palette_value
      local palette_x = geom.stats_x1 + math.floor((geom.stats_total_width - palette_width) / 2)
      fit_item(hdlg, ids.palette, palette_x, geom.board_y2, palette_width)
    end
    for _, change in ipairs(text_changes) do hdlg:SetText(change[1], change[2]) end
    if undo_changed then hdlg:Enable(ids.undo_button, undo_enabled) end
    hdlg:EnableRedraw(true)
  end
  return state
end

function M.apply_status_colors(status, colors)
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

function M.apply_disabled_colors(colors, disabled)
  for key, value in pairs(disabled) do colors[1][key] = value end
  return colors
end

function M.apply_footer_colors(exceeded, colors, disabled)
  for key, value in pairs(disabled) do colors[1][key] = value end
  if exceeded then
    colors[1].Flags = bor(colors[1].Flags, F.FCF_FG_STRIKEOUT)
  end
  return colors
end

return M
