-- Platform-neutral tile rasterizer.
--
-- The console and FAR backends consume the same 2D cell buffer.  This module
-- owns board geometry and tile painting; platform backends only serialize or
-- blit the resulting cells.
local geometry = loader("lib/geometry")
local color = loader("lib/color")
local util = loader("lib/util")

local constants = loader("lib/constants")
local CELL_W, CELL_H = geometry.CELL_W, geometry.CELL_H
local GAP_X = geometry.GAP_X
local LOWER_HALF = "\xe2\x96\x84"
local UPPER_HALF = "\xe2\x96\x80"

local M = {}

local BLACK = { 0, 0, 0 }

local function same_color(a, b)
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function cell_halves(cell)
  if cell[1] == UPPER_HALF then return cell[2], cell[3] end
  if cell[1] == LOWER_HALF then return cell[3], cell[2] end
  return cell[3], cell[3]
end

local function paint_half(buf, half_y, x, bg)
  local y = math.floor(half_y / 2)
  local cell = buf[y + 1][x + 1]
  local top, bottom = cell_halves(cell)
  if half_y % 2 == 0 then top = bg else bottom = bg end
  buf[y + 1][x + 1] = same_color(top, bottom) and { " ", nil, top } or { UPPER_HALF, top, bottom }
end

function M.new_buffer(bg)
  local BOARD_W, BOARD_H = geometry.BOARD_W, geometry.BOARD_H
  local buf = {}
  for y = 1, BOARD_H do
    local row = {}
    for x = 1, BOARD_W do
      row[x] = { " ", nil, bg }
    end
    buf[y] = row
  end
  return buf
end

function M.fill_empty_cells(buf, empty_bg)
  local BOARD_H = geometry.BOARD_H
  for r = 0, constants.BOARD_HEIGHT - 1 do
    for c = 0, constants.BOARD_WIDTH - 1 do
      local x0 = GAP_X + c * (CELL_W + GAP_X)
      local y = geometry.OUTER_INSET_Y + r * geometry.ROW_STRIDE_Y
      if constants.USE_HALF_BLOCKS then
        local start_half = math.max(0, math.min(BOARD_H * 2 - CELL_H * 2, util.round(2 * y)))
        for half_y = start_half, start_half + CELL_H * 2 - 1 do
          for xx = 0, CELL_W - 1 do paint_half(buf, half_y, x0 + xx, empty_bg) end
        end
      else
        local iy = math.max(0, math.min(BOARD_H - CELL_H, util.round(y)))
        for yy = 0, CELL_H - 1 do
          for xx = 0, CELL_W - 1 do buf[iy + yy + 1][x0 + xx + 1] = { " ", nil, empty_bg } end
        end
      end
    end
  end
end

function M.draw_tile(buf, tile, empty_bg, palette, fade)
  local BOARD_W, BOARD_H = geometry.BOARD_W, geometry.BOARD_H
  local alpha = tile.alpha or 1.0
  local bg = tile.bg or color.tile_color(tile.value, palette)
  if alpha < 1.0 then
    bg = util.blend(empty_bg, bg, alpha)
  end
  local fg = tile.fg or color.tile_text_color(tile.value, palette)
  if fade and fade > 0 then
    bg = util.blend(bg, { 0, 0, 0 }, fade)
    fg = util.blend(fg, { 0, 0, 0 }, fade)
  end

  local x = GAP_X + tile.col * (CELL_W + GAP_X)
  local y = geometry.OUTER_INSET_Y + tile.row * geometry.ROW_STRIDE_Y
  local ix = math.max(0, math.min(BOARD_W - CELL_W, util.round(x)))
  local iy = math.max(0, math.min(BOARD_H - CELL_H, util.round(y)))
  local text_row
  if constants.USE_HALF_BLOCKS then
    local start_half = math.max(0, math.min(BOARD_H * 2 - CELL_H * 2, util.round(2 * y)))
    for half_y = start_half, start_half + CELL_H * 2 - 1 do
      for xx = 0, CELL_W - 1 do paint_half(buf, half_y, ix + xx, bg) end
    end
    text_row = math.floor((start_half + CELL_H) / 2)
  else
    for yy = 0, CELL_H - 1 do
      for xx = 0, CELL_W - 1 do buf[iy + yy + 1][ix + xx + 1] = { " ", nil, bg } end
    end
    text_row = iy + math.floor(CELL_H / 2)
  end

  local text = tostring(tile.value)
  local text_col = ix + math.max(0, math.floor((CELL_W - #text) / 2))
  for i = 1, #text do
    local col = text_col + (i - 1)
    if col >= 0 and col < BOARD_W then
      buf[text_row + 1][col + 1] = { text:sub(i, i), fg, bg, true }
    end
  end
end

-- Rasterizes a logical tile list into the shared 2D cell buffer. Platform
-- backends call this once, then serialize or blit the returned cells.
function M.rasterize(tiles, opts)
  opts = opts or {}
  local palette = opts.palette
  local fade = opts.fade or 0
  local board_bg = opts.board_tint or color.board_bg_color(palette)
  local empty_bg = color.empty_color(palette)
  if fade > 0 then
    board_bg = util.blend(board_bg, BLACK, fade)
    empty_bg = util.blend(empty_bg, BLACK, fade)
  end

  local buf = M.new_buffer(board_bg)
  if constants.DRAW_EMPTY_TILES then M.fill_empty_cells(buf, empty_bg) end
  for _, tile in ipairs(tiles or {}) do
    M.draw_tile(buf, tile, empty_bg, palette, fade)
  end
  return buf
end

return M
