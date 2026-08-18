-- Board layout geometry.
local util = loader("lib/util")
local constants = loader("lib/constants")

local M = {}

M.CHAR_ASPECT = constants.CHAR_ASPECT
M.UNIT = constants.GEOMETRY_UNIT
local board_width, board_height = constants.BOARD_WIDTH, constants.BOARD_HEIGHT

function M.compute_cell_dimensions(unit, char_aspect)
  local h = unit
  local accent_width = math.floor(unit / 3 * 2 + 0.5)
  local accent_loss = constants.SHOW_TILE_ACCENTS
    and accent_width / (8 * unit) or 0
  local rendered_loss = constants.SHOW_TILE_ACCENTS
    and ((constants.USE_HALF_BLOCKS and unit % 2 == 0) and 4 or accent_width)
      / (8 * unit) or 0
  -- Keep the aspect based on the visible tile height, not the sacrificed edge.
  local w = math.max(3, util.round(
    h * char_aspect * (1 - rendered_loss) / (1 - accent_loss)
  ))
  return w, h
end

function M.compute_vertical_layout(cell_h, gap_y, use_half_blocks)
  local outer_inset_y = gap_y
  if use_half_blocks and cell_h % 2 == 0 then
    outer_inset_y = 0.5
  end
  return outer_inset_y, cell_h + gap_y
end

local function recalculate()
  M.CELL_W, M.CELL_H = M.compute_cell_dimensions(M.UNIT, M.CHAR_ASPECT)
  M.GAP_X, M.GAP_Y = 2, 1
  M.OUTER_INSET_Y, M.ROW_STRIDE_Y = M.compute_vertical_layout(M.CELL_H, M.GAP_Y, constants.USE_HALF_BLOCKS)
  M.BOARD_W = board_width * M.CELL_W + (board_width + 1) * M.GAP_X
  M.BOARD_H = math.ceil(
    board_height * M.CELL_H
    + (board_height - 1) * M.GAP_Y
    + 2 * M.OUTER_INSET_Y
  )
end

function M.set_unit(unit)
  M.UNIT = math.max(2, unit)
  recalculate()
end

function M.set_board_dimensions(width, height)
  board_width, board_height = width, height
  recalculate()
end

recalculate()

return M
