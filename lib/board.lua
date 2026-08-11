-- Pure 2048 board/game logic. No I/O, no FFI.
local M = {}
local constants = loader("lib/constants")

M.WIN_INDEX = constants.WIN_INDEX

local function dimensions(board)
  if board then
    return #(board[1] or {}), #board
  end
  return constants.BOARD_WIDTH, constants.BOARD_HEIGHT
end

function M.new_empty_board()
  local BOARD_WIDTH, BOARD_HEIGHT = dimensions()
  local b = {}
  for r = 1, BOARD_HEIGHT do
    b[r] = {}
    for c = 1, BOARD_WIDTH do
      b[r][c] = 0
    end
  end
  return b
end

function M.copy_board(board)
  local BOARD_WIDTH, BOARD_HEIGHT = dimensions(board)
  local b = {}
  for r = 1, BOARD_HEIGHT do
    b[r] = {}
    for c = 1, BOARD_WIDTH do
      b[r][c] = board[r][c]
    end
  end
  return b
end

function M.boards_equal(a, b)
  local BOARD_WIDTH, BOARD_HEIGHT = dimensions(a)
  for r = 1, BOARD_HEIGHT do
    for c = 1, BOARD_WIDTH do
      if a[r][c] ~= b[r][c] then return false end
    end
  end
  return true
end

local function coord(direction, line_index, k, board)
  local BOARD_WIDTH, BOARD_HEIGHT = dimensions(board)
  if direction == "left" then
    return line_index, k
  elseif direction == "right" then
    return line_index, BOARD_WIDTH + 1 - k
  elseif direction == "up" then
    return k, line_index
  elseif direction == "down" then
    return BOARD_HEIGHT + 1 - k, line_index
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
      local new_val = v + 1
      local target = #result + 1
      moves[#moves + 1] = { from_k = k, to_k = target, value = v, merged = false }
      moves[#moves + 1] = { from_k = k2, to_k = target, value = v2, merged = true }
      result[#result + 1] = new_val
      score = score + 2 ^ new_val
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
  local BOARD_WIDTH, BOARD_HEIGHT = dimensions(board)
  local new_board = {}
  for r = 1, BOARD_HEIGHT do
    new_board[r] = {}
    for c = 1, BOARD_WIDTH do new_board[r][c] = 0 end
  end
  local all_moves = {}
  local total_score = 0

  local line_count = (direction == "left" or direction == "right") and BOARD_HEIGHT or BOARD_WIDTH
  local line_length = (direction == "left" or direction == "right") and BOARD_WIDTH or BOARD_HEIGHT
  for line_index = 1, line_count do
    local vals = {}
    for k = 1, line_length do
      local r, c = coord(direction, line_index, k, board)
      local v = board[r][c]
      if v ~= 0 then
        vals[#vals + 1] = { value = v, k = k }
      end
    end

    local result, moves, score = process_line(vals)
    total_score = total_score + score

    for k, v in ipairs(result) do
      local r, c = coord(direction, line_index, k, board)
      new_board[r][c] = v
    end

    for _, mv in ipairs(moves) do
      local fr, fc = coord(direction, line_index, mv.from_k, board)
      local tr, tc = coord(direction, line_index, mv.to_k, board)
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
  local BOARD_WIDTH, BOARD_HEIGHT = dimensions(board)
  local empties = {}
  for r = 1, BOARD_HEIGHT do
    for c = 1, BOARD_WIDTH do
      if board[r][c] == 0 then
        empties[#empties + 1] = { r, c }
      end
    end
  end
  if #empties == 0 then return nil end
  local pick = empties[math.random(#empties)]
  local r, c = pick[1], pick[2]
  board[r][c] = (math.random() < constants.SPAWN_FOUR_PROBABILITY) and 2 or 1
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
  local BOARD_WIDTH, BOARD_HEIGHT = dimensions(board)
  for r = 1, BOARD_HEIGHT do
    for c = 1, BOARD_WIDTH do
      if board[r][c] >= M.WIN_INDEX then return true end
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
