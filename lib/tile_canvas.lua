-- Platform-neutral tile rasterizer.
--
-- The console and FAR backends consume the same 2D cell buffer.  This module
-- owns board geometry and tile painting; platform backends only serialize or
-- blit the resulting cells.
local geometry = loader("lib/geometry")
local color = loader("lib/color")
local util = loader("lib/util")

local BOARD_SIZE = loader("lib/constants").BOARD_SIZE
local CELL_W, CELL_H = geometry.CELL_W, geometry.CELL_H
local GAP_X, GAP_Y = geometry.GAP_X, geometry.GAP_Y
local BOARD_W, BOARD_H = geometry.BOARD_W, geometry.BOARD_H
local HALF_BLOCKS = geometry.HALF_BLOCKS
local LOWER_HALF = "\xe2\x96\x84"
local UPPER_HALF = "\xe2\x96\x80"

local M = {}

local BLACK = { 0, 0, 0 }

function M.new_buffer(bg)
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
  for r = 0, BOARD_SIZE - 1 do
    for c = 0, BOARD_SIZE - 1 do
      local x0 = GAP_X + c * (CELL_W + GAP_X)
      local y0 = GAP_Y + r * (CELL_H + GAP_Y)
      for yy = 0, CELL_H - 1 do
        for xx = 0, CELL_W - 1 do
          buf[y0 + yy + 1][x0 + xx + 1] = { " ", nil, empty_bg }
        end
      end
    end
  end
end

function M.draw_tile(buf, tile, empty_bg, palette, fade)
  local alpha = tile.alpha or 1.0
  local bg = tile.bg or color.tile_color(tile.value, palette)
  if alpha < 1.0 then
    bg = util.blend(empty_bg, bg, alpha)
  end
  local fg = tile.fg or color.text_color(bg)
  if fade and fade > 0 then
    bg = util.blend(bg, { 0, 0, 0 }, fade)
    fg = util.blend(fg, { 0, 0, 0 }, fade)
  end

  local x = GAP_X + tile.col * (CELL_W + GAP_X)
  local y = GAP_Y + tile.row * (CELL_H + GAP_Y)
  local ix = math.max(0, math.min(BOARD_W - CELL_W, util.round(x)))
  local iy = math.max(0, math.min(BOARD_H - CELL_H, util.round(y)))

  for yy = 0, CELL_H - 1 do
    for xx = 0, CELL_W - 1 do
      buf[iy + yy + 1][ix + xx + 1] = { " ", nil, bg }
    end
  end

  if HALF_BLOCKS then
    for xx = 0, CELL_W - 1 do
      buf[iy + 1][ix + xx + 1] = { LOWER_HALF, bg, empty_bg }
      buf[iy + CELL_H][ix + xx + 1] = { UPPER_HALF, bg, empty_bg }
    end
  end

  local text = tostring(tile.value)
  local text_row = iy + math.floor(CELL_H / 2)
  local text_col = ix + math.max(0, math.floor((CELL_W - #text) / 2))
  for i = 1, #text do
    local col = text_col + (i - 1)
    if col >= 0 and col < BOARD_W then
      buf[text_row + 1][col + 1] = { text:sub(i, i), fg, bg }
    end
  end
end

-- Rasterizes a logical tile list into the shared 2D cell buffer. Platform
-- backends call this once, then serialize or blit the returned cells.
function M.rasterize(tiles, opts)
  opts = opts or {}
  local palette = opts.palette
  local fade = opts.fade or 0
  local board_bg = opts.board_tint or color.empty_color(palette)
  local empty_bg = board_bg
  if fade > 0 then
    empty_bg = util.blend(board_bg, BLACK, fade)
  end

  local buf = M.new_buffer(empty_bg)
  M.fill_empty_cells(buf, empty_bg)
  for _, tile in ipairs(tiles or {}) do
    M.draw_tile(buf, tile, empty_bg, palette, fade)
  end
  return buf
end

return M
