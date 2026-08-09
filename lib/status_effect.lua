-- Shared visual effects for terminal states and pause.
local color = loader("lib/color")
local util = loader("lib/util")

local M = {}

function M.compute(status, paused, palette, time)
  time = time or 0
  if status == "game_over" then
    local board_bg = color.board_bg_color(palette)
    local pulse = 0.20 + 0.15 * (0.5 + 0.5 * math.sin(time * 3.0))
    return { board_tint = util.blend(board_bg, { 140, 25, 25 }, pulse), fade = 0, blink = true }
  end
  if status == "won" then
    local board_bg = color.board_bg_color(palette)
    local pulse = 0.10 + 0.10 * (0.5 + 0.5 * math.sin(time * 2.0))
    return { board_tint = util.blend(board_bg, { 255, 200, 60 }, pulse), fade = 0, blink = true }
  end
  if paused then
    return { board_tint = nil, fade = 0.55, blink = true }
  end
  return { board_tint = nil, fade = 0, blink = false }
end

return M
