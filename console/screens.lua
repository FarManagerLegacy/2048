-- End-of-game / pause screens (console backend, blocking loops).
local render = loader("console/render")
local tiles_mod = loader("lib/tiles")
local color = loader("lib/color")
local util = loader("lib/util")
local platform = loader("console/platform")
local constants = loader("lib/constants")
local config = loader("console/config")

local M = {}

local function read_key()
  local key = platform.read_key()
  platform.flush_input()
  return key
end

function M.game_over_screen(board, score, best, moves_count, elapsed_seconds, can_undo, palette)
  local tiles = tiles_mod.board_to_tiles(board)
  local board_bg = color.board_bg_color(palette)
  local danger = { 140, 25, 25 }
  local start = platform.now()
  while true do
    if platform.kbhit() then
      local key = read_key()
      if key == "undo" and can_undo then return "undo" end
      if key == "restart" or key == "quit" then return key end
    end
    local t = platform.now() - start
    local pulse = 0.20 + 0.15 * (0.5 + 0.5 * math.sin(t * 3.0))
    local tint = util.blend(board_bg, danger, pulse)
    local blink_on = (t % 1.0) < 0.6
    render.render_frame({
      tiles = tiles, score = score, best = best, moves_count = moves_count,
      elapsed_seconds = elapsed_seconds, status_text = "GAME OVER",
      status_color = { 255, 90, 90 }, board_tint = tint, blink_on = blink_on,
      palette = palette,
    })
    platform.sleep(config.END_SCREEN_TICK)
  end
end

function M.win_screen(board, score, best, moves_count, elapsed_seconds, can_undo, palette)
  local tiles = tiles_mod.board_to_tiles(board)
  local board_bg = color.board_bg_color(palette)
  local gold = { 255, 200, 60 }
  local BOARD_SIZE = constants.BOARD_SIZE
  local empties = {}
  for r = 1, BOARD_SIZE do
    for c = 1, BOARD_SIZE do
      if board[r][c] == 0 then empties[#empties + 1] = { r - 1, c - 1 } end
    end
  end
  local sparkle_chars = { "*", "+", "." }
  local start = platform.now()
  while true do
    if platform.kbhit() then
      local key = read_key()
      if key == "undo" and can_undo then return "undo" end
      if key == "restart" or key == "quit" then return key end
    end
    local t = platform.now() - start
    local pulse = 0.10 + 0.10 * (0.5 + 0.5 * math.sin(t * 2.0))
    local tint = util.blend(board_bg, gold, pulse)
    local hue = (t * 0.25) % 1.0
    local r, g, b = util.hsv_to_rgb(hue, 0.75, 1.0)
    local msg_color = { util.trunc(r * 255), util.trunc(g * 255), util.trunc(b * 255) }

    local sparkles = {}
    for _, rc in ipairs(empties) do
      if math.random() < 0.35 then
        local hue_s = math.random()
        local sr, sg, sb = util.hsv_to_rgb(hue_s, 0.6, 1.0)
        local sp_color = { util.trunc(sr * 255), util.trunc(sg * 255), util.trunc(sb * 255) }
        local ch = sparkle_chars[math.random(#sparkle_chars)]
        sparkles[#sparkles + 1] = { rc = rc, color = sp_color, ch = ch }
      end
    end

    render.render_frame({
      tiles = tiles, score = score, best = best, moves_count = moves_count,
      elapsed_seconds = elapsed_seconds, status_text = "YOU WIN! 2048",
      status_color = msg_color, board_tint = tint, blink_on = true,
      sparkles = sparkles, palette = palette,
    })
    platform.sleep(config.END_SCREEN_TICK)
  end
end

function M.pause_screen(board, score, best, moves_count, elapsed_seconds, palette)
  local tiles = tiles_mod.board_to_tiles(board)
  local start = platform.now()
  while true do
    if platform.kbhit() then
      local key = read_key()
      if key == "pause" or key == "quit" then return key end
    end
    local t = platform.now() - start
    local blink_on = (t % 1.0) < 0.6
    render.render_frame({
      tiles = tiles, score = score, best = best, moves_count = moves_count,
      elapsed_seconds = elapsed_seconds, status_text = "PAUSED",
      status_color = { 150, 190, 255 }, blink_on = blink_on, paused = true,
      palette = palette,
    })
    platform.sleep(config.END_SCREEN_TICK)
  end
end

return M
