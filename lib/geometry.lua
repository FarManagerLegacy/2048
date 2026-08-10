-- Board layout geometry.
local util = loader("lib/util")
local constants = loader("lib/constants")

local M = {}

M.CHAR_ASPECT = constants.GEOMETRY_CHAR_ASPECT
M.UNIT = constants.GEOMETRY_UNIT

function M.compute_cell_dimensions(unit, char_aspect)
  local h = unit
  local w = math.max(3, util.round(h * char_aspect))
  return w, h
end

function M.compute_vertical_layout(cell_h, gap_y, use_half_blocks)
  local outer_inset_y = gap_y
  if use_half_blocks and cell_h % 2 == 0 then
    outer_inset_y = 0.5
  end
  return outer_inset_y, cell_h + gap_y
end

M.CELL_W, M.CELL_H = M.compute_cell_dimensions(M.UNIT, M.CHAR_ASPECT)
M.GAP_X, M.GAP_Y = 2, 1
M.OUTER_INSET_Y, M.ROW_STRIDE_Y = M.compute_vertical_layout(M.CELL_H, M.GAP_Y, constants.USE_HALF_BLOCKS)

M.BOARD_W = constants.BOARD_SIZE * M.CELL_W + (constants.BOARD_SIZE + 1) * M.GAP_X
M.BOARD_H = math.ceil(
  constants.BOARD_SIZE * M.CELL_H
  + (constants.BOARD_SIZE - 1) * M.GAP_Y
  + 2 * M.OUTER_INSET_Y
)

return M
