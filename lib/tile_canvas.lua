-- Platform-neutral tile rasterizer.
--
-- The console and FAR backends consume the same 2D cell buffer.  This module
-- owns board geometry and tile painting; platform backends only serialize or
-- blit the resulting cells.
local geometry = loader("lib/geometry")
local color = loader("lib/color")
local util = loader("lib/util")

local constants = loader("lib/constants")
local LOWER_HALF = "▄"
local UPPER_HALF = "▀"
local ACCENT_SYMBOLS = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local ACCENT_SYMBOL_SET = {}
for _, symbol in ipairs(ACCENT_SYMBOLS) do ACCENT_SYMBOL_SET[symbol] = true end

local function accent_symbols(unit)
  local width = math.floor(unit / 3 * 2 + 0.5)
  return ACCENT_SYMBOLS[width], ACCENT_SYMBOLS[8 - width]
end

local M = {}

local BLACK = { 0, 0, 0 }

local function same_color(a, b)
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function cell_halves(cell)
  if cell[1] == UPPER_HALF then return cell[2], cell[3] end
  if cell[1] == LOWER_HALF then return cell[3], cell[2] end
  if ACCENT_SYMBOL_SET[cell[1]] then return cell[3], cell[2] end
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
  local cell_w, cell_h = geometry.CELL_W, geometry.CELL_H
  local gap_x, board_h = geometry.GAP_X, geometry.BOARD_H
  for r = 0, constants.BOARD_HEIGHT - 1 do
    for c = 0, constants.BOARD_WIDTH - 1 do
      local x0 = gap_x + c * (cell_w + gap_x)
      local y = geometry.OUTER_INSET_Y + r * geometry.ROW_STRIDE_Y
      if constants.USE_HALF_BLOCKS then
        local half_height = cell_h * 2
        if constants.SHOW_TILE_ACCENTS and cell_h % 2 == 0 then
          -- Match the half-block accent trick's lost 4/8 of the cell.
          half_height = half_height - 1
        end
        local start_half = math.max(0, math.min(board_h * 2 - cell_h * 2, util.round(2 * y)))
        for half_y = start_half, start_half + half_height - 1 do
          for xx = 0, cell_w - 1 do paint_half(buf, half_y, x0 + xx, empty_bg) end
        end
        if constants.SHOW_TILE_ACCENTS and cell_h % 2 == 0 then
          local _, inverted_accent_symbol = accent_symbols(geometry.UNIT)
          local boundary_row = math.floor((start_half + half_height) / 2)
          for xx = 0, cell_w - 1 do
            local cell = buf[boundary_row + 1][x0 + xx + 1]
            local _, bottom = cell_halves(cell)
            -- Keep the accent's fractional 1/8 instead of dropping it too.
            buf[boundary_row + 1][x0 + xx + 1] = {
              inverted_accent_symbol, bottom, empty_bg,
            }
          end
        end
      else
        local iy = math.max(0, math.min(board_h - cell_h, util.round(y)))
        for yy = 0, cell_h - 1 do
          for xx = 0, cell_w - 1 do buf[iy + yy + 1][x0 + xx + 1] = { " ", nil, empty_bg } end
        end
      end
    end
  end
end

function M.draw_tile(buf, tile, empty_bg, palette, fade)
  local cell_w, cell_h = geometry.CELL_W, geometry.CELL_H
  local gap_x, board_w, board_h = geometry.GAP_X, geometry.BOARD_W, geometry.BOARD_H
  local alpha = tile.alpha or 1.0
  local bg = tile.bg or color.tile_color(tile.value, palette)
  if alpha < 1.0 then
    bg = util.blend(empty_bg, bg, alpha)
  end
  local fg = tile.fg or color.tile_text_color(tile.value, palette)
  local accent_fg = color.tile_accent_color(tile.value, palette)
  local accent_symbol, inverted_accent_symbol = accent_symbols(geometry.UNIT)
  if accent_fg then
    if alpha < 1.0 then
      accent_fg = util.blend(empty_bg, accent_fg, alpha)
    end
    if fade and fade > 0 then
      accent_fg = util.blend(accent_fg, BLACK, fade)
    end
  end
  if fade and fade > 0 then
    bg = util.blend(bg, { 0, 0, 0 }, fade)
    fg = util.blend(fg, { 0, 0, 0 }, fade)
  end
  local x = gap_x + tile.col * (cell_w + gap_x)
  local y = geometry.OUTER_INSET_Y + tile.row * geometry.ROW_STRIDE_Y
  local ix = math.max(0, math.min(board_w - cell_w, util.round(x)))
  local iy = math.max(0, math.min(board_h - cell_h, util.round(y)))
  local text_row
  if constants.USE_HALF_BLOCKS then
    local start_half = math.max(0, math.min(board_h * 2 - cell_h * 2, util.round(2 * y)))
    for half_y = start_half, start_half + cell_h * 2 - 1 do
      for xx = 0, cell_w - 1 do paint_half(buf, half_y, ix + xx, bg) end
    end
    local last_half = start_half + cell_h * 2 - 1
    local bottom_row = math.floor(last_half / 2)
    if constants.SHOW_TILE_ACCENTS then
      accent_fg = accent_fg or util.blend(bg, BLACK, 0.3)
      if last_half % 2 == 1 then
        for xx = 0, cell_w - 1 do
          buf[bottom_row + 1][ix + xx + 1] = { accent_symbol, accent_fg, bg }
        end
      else
        for xx = 0, cell_w - 1 do
          local cell = buf[bottom_row + 1][ix + xx + 1]
          local _, bottom = cell_halves(cell)
          -- There are no upper fractional blocks: invert the matching lower one.
          buf[bottom_row + 1][ix + xx + 1] = {
            inverted_accent_symbol, bottom, accent_fg,
          }
        end
      end
    end
    text_row = math.floor((start_half + cell_h) / 2)
  else
    for yy = 0, cell_h - 1 do
      for xx = 0, cell_w - 1 do buf[iy + yy + 1][ix + xx + 1] = { " ", nil, bg } end
    end
    if constants.SHOW_TILE_ACCENTS then
      accent_fg = accent_fg or util.blend(bg, BLACK, 0.3)
      for xx = 0, cell_w - 1 do
        buf[iy + cell_h][ix + xx + 1] = { accent_symbol, accent_fg, bg }
      end
    end
    text_row = iy + ((not constants.USE_HALF_BLOCKS
      and constants.SHOW_TILE_ACCENTS and cell_h == 2)
      and 0 or math.floor(cell_h / 2))
  end

  local text = tostring(2 ^ tile.value)
  local text_col = ix + math.max(0, math.floor((cell_w - #text) / 2))
  for i = 1, #text do
    local col = text_col + (i - 1)
    if col >= 0 and col < board_w then
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
    if opts.tile_effect and tile.row == opts.tile_effect.row
        and tile.col == opts.tile_effect.col then
      tile = {
        row = tile.row, col = tile.col, value = tile.value,
        alpha = tile.alpha, bg = opts.tile_effect.bg, fg = opts.tile_effect.fg,
      }
    end
    M.draw_tile(buf, tile, empty_bg, palette, fade)
  end
  return buf
end

return M
