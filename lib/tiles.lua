-- Platform-neutral conversion from a board matrix to renderable tile records.
local board_mod = loader("lib/board")

local M = {}

function M.board_to_tiles(board)
  local tiles = {}
  for r = 1, board_mod.BOARD_SIZE do
    for c = 1, board_mod.BOARD_SIZE do
      if board[r][c] ~= 0 then
        tiles[#tiles + 1] = { row = r - 1, col = c - 1, value = board[r][c] }
      end
    end
  end
  return tiles
end

return M
