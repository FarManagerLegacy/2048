-- Pure 2048 board/game logic. No I/O, no FFI.
local M = {}
local constants = loader("lib/constants")

M.BOARD_SIZE = constants.BOARD_SIZE
M.WIN_VALUE = constants.WIN_VALUE

local BOARD_SIZE = M.BOARD_SIZE

function M.new_empty_board()
  local b = {}
  for r = 1, BOARD_SIZE do
    b[r] = {}
    for c = 1, BOARD_SIZE do
      b[r][c] = 0
    end
  end
  return b
end

function M.copy_board(board)
  local b = {}
  for r = 1, BOARD_SIZE do
    b[r] = {}
    for c = 1, BOARD_SIZE do
      b[r][c] = board[r][c]
    end
  end
  return b
end

function M.boards_equal(a, b)
  for r = 1, BOARD_SIZE do
    for c = 1, BOARD_SIZE do
      if a[r][c] ~= b[r][c] then return false end
    end
  end
  return true
end

local function coord(direction, line_index, k)
  local flip = BOARD_SIZE + 1 - k
  if direction == "left" then
    return line_index, k
  elseif direction == "right" then
    return line_index, flip
  elseif direction == "up" then
    return k, line_index
  elseif direction == "down" then
    return flip, line_index
  else
    error("unknown direction: " .. tostring(direction))
  end
end
M._coord = coord

local function process_line(values)
  local result = {}
  local moves = {}
  local score = 0
  local i, n = 1, #values
  while i <= n do
    local v, k = values[i].value, values[i].k
    if i + 1 <= n and values[i + 1].value == v then
      local v2, k2 = values[i + 1].value, values[i + 1].k
      local new_val = v * 2
      local target = #result + 1
      moves[#moves + 1] = { from_k = k, to_k = target, value = v, merged = false }
      moves[#moves + 1] = { from_k = k2, to_k = target, value = v2, merged = true }
      result[#result + 1] = new_val
      score = score + new_val
      i = i + 2
    else
      local target = #result + 1
      moves[#moves + 1] = { from_k = k, to_k = target, value = v, merged = false }
      result[#result + 1] = v
      i = i + 1
    end
  end
  return result, moves, score
end
M._process_line = process_line

function M.move_board(board, direction)
  local new_board = M.new_empty_board()
  local all_moves = {}
  local total_score = 0

  for line_index = 1, BOARD_SIZE do
    local vals = {}
    for k = 1, BOARD_SIZE do
      local r, c = coord(direction, line_index, k)
      local v = board[r][c]
      if v ~= 0 then
        vals[#vals + 1] = { value = v, k = k }
      end
    end

    local result, moves, score = process_line(vals)
    total_score = total_score + score

    for k, v in ipairs(result) do
      local r, c = coord(direction, line_index, k)
      new_board[r][c] = v
    end

    for _, mv in ipairs(moves) do
      local fr, fc = coord(direction, line_index, mv.from_k)
      local tr, tc = coord(direction, line_index, mv.to_k)
      all_moves[#all_moves + 1] = {
        fr = fr, fc = fc, tr = tr, tc = tc,
        value = mv.value, merged = mv.merged,
      }
    end
  end

  local changed = not M.boards_equal(new_board, board)
  return new_board, all_moves, total_score, changed
end

function M.spawn_tile(board)
  local empties = {}
  for r = 1, BOARD_SIZE do
    for c = 1, BOARD_SIZE do
      if board[r][c] == 0 then
        empties[#empties + 1] = { r, c }
      end
    end
  end
  if #empties == 0 then return nil end
  local pick = empties[math.random(#empties)]
  local r, c = pick[1], pick[2]
  board[r][c] = (math.random() < constants.SPAWN_FOUR_PROBABILITY) and 4 or 2
  return { r = r, c = c, value = board[r][c] }
end

function M.any_move_possible(board)
  for _, d in ipairs({ "left", "right", "up", "down" }) do
    local _, _, _, changed = M.move_board(board, d)
    if changed then return true end
  end
  return false
end

function M.has_won(board)
  for r = 1, BOARD_SIZE do
    for c = 1, BOARD_SIZE do
      if board[r][c] >= M.WIN_VALUE then return true end
    end
  end
  return false
end

function M.compute_status(board)
  if M.has_won(board) then return "won" end
  if not M.any_move_possible(board) then return "game_over" end
  return ""
end

return M
