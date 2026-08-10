-- Color palettes and tile/text color helpers.
local util = loader("lib/util")

local M = {}

local def_tiles = {
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
}

M.PALETTES = {
  classic = {
    board_bg = { 187, 173, 160 },
    empty = { 205, 193, 180 },
    tiles = def_tiles,
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
  original = {
    board_bg = { 152, 136, 118 },
    empty = { 186, 172, 154 },
    text_dark = { 117, 100, 82 },
    text_light = { 255, 255, 255 },
    tiles = def_tiles,
  },
  ["original-dark"] = {
    board_bg = { 80, 76, 68 },
    empty = { 107, 102, 91 },
    tiles = def_tiles,
  },
  amber = {
    board_bg = { 247, 206, 139 },
    empty = { 251, 216, 155 },
    text_dark = { 213, 92, 38 },
    text_light = { 255, 255, 255 },
    tiles = {
      [2] = { 244, 186, 97 },
      [4] = { 242, 171, 71 },
      [8] = { 241, 157, 56 },
      [16] = { 236, 146, 53 },
    },
  },
  rose = {
    board_bg = { 239, 189, 207 },
    empty = { 244, 201, 215 },
    text_dark = { 159, 39, 87 },
    text_light = { 255, 255, 255 },
    tiles = {
      [2] = { 230, 148, 176 },
      [4] = { 223, 107, 146 },
      [8] = { 218, 79, 122 },
      [16] = { 214, 56, 100 },
      [32] = { 198, 51, 97 },
    },
  },
  sky = {
    board_bg = { 194, 221, 248 },
    empty = { 203, 227, 250 },
    text_dark = { 2, 136, 209 },
    text_light = { 255, 255, 255 },
    tiles = {
      [2] = { 171, 218, 247 },
      [4] = { 148, 210, 246 },
      [8] = { 112, 192, 242 },
      [16] = { 90, 179, 240 },
      [32] = { 75, 166, 238 },
      [64] = { 69, 153, 223 },
      [128] = { 59, 134, 203 },
    },
  },
  mint = {
    board_bg = { 206, 229, 203 },
    empty = { 225, 239, 222 },
    text_dark = { 46, 125, 50 },
    text_light = { 255, 255, 255 },
    tiles = {
      [2] = { 175, 213, 171 },
      [4] = { 145, 197, 138 },
      [8] = { 123, 185, 114 },
      [32] = { 93, 158, 82 },
    },
  },
  ["mint-dark"] = {
    board_bg = { 21, 23, 20 },
    empty = { 44, 46, 42 },
    text_dark = { 68, 122, 58 },
    text_light = { 255, 255, 255 },
    tiles = {
      [2] = { 175, 213, 171 },
      [4] = { 145, 197, 138 },
      [8] = { 123, 185, 114 },
      [16] = { 103, 173, 91 },
    },
  }
}

M._PALETTE_NAMES = {
  "classic", "original", "original-dark", "mint", "mint-dark",
  "gradient", "ocean", "amber", "rose", "sky"
}

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

-- Palettes may define only part of the tile range. Exact colors win; values
-- below the smallest defined tile reuse that color, while larger values are
-- extrapolated from the largest defined tile in HSV.
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

function M.tile_text_color(value, palette_name)
  local palette = resolve_palette(palette_name)
  if value == 2 or value == 4 then
    return palette.text_dark or { 119, 110, 101 }
  end
  return palette.text_light or { 249, 246, 242 }
end

return M
