-- Shared visual effects for terminal states and pause.
local color = loader("lib/color")
local constants = loader("lib/constants")
local util = loader("lib/util")

local M = {}

local function luminance(rgb)
  return 0.299 * rgb[1] + 0.587 * rgb[2] + 0.114 * rgb[3]
end

function M.compute(status, paused, palette, time, victory)
  time = time or 0
  if status == "game_over" then
    local board_bg = color.board_bg_color(palette)
    local signal = luminance(board_bg) > 128 and { 35, 35, 35 } or { 235, 235, 235 }
    local pulse = 0.20 + 0.15 * (0.5 + 0.5 * math.sin(time * 3.0))
    return {
      board_tint = util.blend(board_bg, signal, pulse),
      fade = 0,
      blink = true,
    }
  end
  if status == "won" and not victory then
    return { board_tint = nil, fade = 0, blink = true }
  end
  if paused then
    return { board_tint = nil, fade = 0.55, blink = true }
  end
  if victory then
    local tile_bg = color.tile_color(victory.value, palette)
    local signal = color.empty_color(palette)
    local elapsed = victory.elapsed or time
    local pulse = 0.5 - 0.5 * math.cos(
      elapsed * 2 * math.pi / constants.VICTORY_EFFECT_PHASE_SECONDS)
    local effect_bg = util.blend(tile_bg, signal, pulse)
    return {
      board_tint = nil,
      fade = 0,
      blink = false,
      tile_effect = {
        row = victory.row - 1,
        col = victory.col - 1,
        bg = effect_bg,
        fg = luminance(effect_bg) > 128
          and color.tile_text_color(1, palette)
          or color.tile_text_color(4, palette),
      },
    }
  end
  return { board_tint = nil, fade = 0, blink = false }
end

return M
