-- Board layout geometry.
local util = loader("lib/util")
local constants = loader("lib/constants")

local M = {}

M.CHAR_ASPECT = constants.GEOMETRY_CHAR_ASPECT
M.UNIT = constants.GEOMETRY_UNIT

function M.compute_cell_dimensions(unit, char_aspect)
  local h = unit
  local w = math.max(3, util.round(h * char_aspect))
  if h % 2 == 0 then h = h + 1 end
  return w, h
end

function M.compute_gaps(unit)
  -- Keep the visual separation between tiles fixed when tile size changes.
  local gap_y = unit % 2 == 0 and 0 or 1
  return 2, gap_y
end

M.CELL_W, M.CELL_H = M.compute_cell_dimensions(M.UNIT, M.CHAR_ASPECT)
M.GAP_X, M.GAP_Y = M.compute_gaps(M.UNIT)
M.HALF_BLOCKS = M.UNIT % 2 == 0

M.BOARD_W = constants.BOARD_SIZE * M.CELL_W + (constants.BOARD_SIZE + 1) * M.GAP_X
M.BOARD_H = constants.BOARD_SIZE * M.CELL_H + (constants.BOARD_SIZE + 1) * M.GAP_Y

return M
