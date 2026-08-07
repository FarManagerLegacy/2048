-- Color palettes and tile/text color helpers.
local util = loader("lib/util")

local M = {}

M.PALETTES = {
  classic = {
    board_bg = { 187, 173, 160 },
    empty = { 205, 193, 180 },
    tiles = {
      [2] = { 238, 228, 218 },
      [4] = { 237, 224, 200 },
      [8] = { 242, 177, 121 },
      [16] = { 245, 149, 99 },
      [32] = { 246, 124, 95 },
      [64] = { 246, 94, 59 },
      [128] = { 237, 207, 114 },
      [256] = { 237, 204, 97 },
      [512] = { 237, 200, 80 },
      [1024] = { 237, 197, 63 },
      [2048] = { 237, 194, 46 },
    },
  },
  gradient = {
    board_bg = { 48, 52, 63 },
    empty = { 58, 62, 74 },
    tiles = {
      [2] = { 238, 228, 218 },
      [4] = { 223, 209, 168 },
    },
  },
  ocean = {
    board_bg = { 24, 62, 79 },
    empty = { 34, 78, 97 },
    tiles = {
      [2] = { 224, 247, 250 },
      [4] = { 178, 235, 242 },
    },
  },
}

M._PALETTE_NAMES = { "classic", "gradient", "ocean" }

function M.cycle_palette(current)
  local names = M._PALETTE_NAMES
  current = current or "classic"
  local idx
  for i, name in ipairs(names) do
    if name == current then idx = i break end
  end
  idx = idx or 1
  local next_idx = (idx % #names) + 1
  local next_name = names[next_idx]
  return next_name
end

local function resolve_palette(name)
  name = name or "classic"
  return M.PALETTES[name] or M.PALETTES.classic
end

local function tiles_min_key(tiles)
  local m = nil
  for k in pairs(tiles) do
    if m == nil or k < m then m = k end
  end
  return m
end

local function tiles_max_key(tiles)
  local m = nil
  for k in pairs(tiles) do
    if m == nil or k > m then m = k end
  end
  return m
end

local function extrapolate_color(value, palette)
  local tiles = palette.tiles
  local max_key = tiles_max_key(tiles)
  local max_power = util.bit_length(max_key) - 1
  local power = util.bit_length(value) - 1
  local extra = power - max_power
  local base = tiles[max_key]
  local hue_base, sat_base, val_base = util.rgb_to_hsv(base[1] / 255, base[2] / 255, base[3] / 255)
  local hue = (hue_base - 0.045 * extra) % 1.0
  local sat = math.min(1.0, sat_base + 0.05 * extra)
  local val = math.max(0.25, val_base - 0.05 * extra)
  local r, g, b = util.hsv_to_rgb(hue, sat, val)
  return { util.trunc(r * 255), util.trunc(g * 255), util.trunc(b * 255) }
end

function M.tile_color(value, palette_name)
  local palette = resolve_palette(palette_name)
  local tiles = palette.tiles
  if tiles[value] then return tiles[value] end
  local min_key = tiles_min_key(tiles)
  if value < min_key then return tiles[min_key] end
  return extrapolate_color(value, palette)
end

function M.board_bg_color(palette_name)
  return resolve_palette(palette_name).board_bg
end

function M.empty_color(palette_name)
  return resolve_palette(palette_name).empty
end

function M.text_color(bg)
  local r, g, b = bg[1], bg[2], bg[3]
  local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
  if luminance > 150 then
    return { 60, 56, 50 }
  end
  return { 249, 246, 242 }
end

return M
