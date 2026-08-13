local board_mod = loader("lib/board")

local M = {}
local directions = board_mod.DIRECTIONS
local LOSS_PENALTY = 1e9

local function dimensions(board)
  return #(board[1] or {}), #board
end

local function monotonic_score(board, start_r, start_c, step_r, step_c)
  local width, height = dimensions(board)
  local score = 0
  for r = start_r, start_r + (height - 1) * step_r, step_r do
    for c = start_c, start_c + (width - 1) * step_c, step_c do
      local value = board[r][c]
      local next_c, next_r = c + step_c, r + step_r
      if value ~= 0 and next_c >= 1 and next_c <= width and board[r][next_c] ~= 0 then
        score = score + (value >= board[r][next_c] and value or -value)
      end
      if value ~= 0 and next_r >= 1 and next_r <= height and board[next_r][c] ~= 0 then
        score = score + (value >= board[next_r][c] and value or -value)
      end
    end
  end
  return score
end

local function heuristic(board)
  local width, height = dimensions(board)
  local empty, smooth = 0, 0
  local max_value, corner = 0, 0
  for r = 1, height do
    for c = 1, width do
      local value = board[r][c]
      if value == 0 then
        empty = empty + 1
      else
        local is_corner = (r == 1 or r == height) and (c == 1 or c == width)
        if value > max_value then
          max_value, corner = value, is_corner and value or 0
        elseif value == max_value and is_corner then
          corner = value
        end
        if c < width and board[r][c + 1] ~= 0 then
          smooth = smooth - math.abs(value - board[r][c + 1])
        end
        if r < height and board[r + 1][c] ~= 0 then
          smooth = smooth - math.abs(value - board[r + 1][c])
        end
      end
    end
  end
  local monotonic = math.max(
    monotonic_score(board, 1, 1, 1, 1),
    monotonic_score(board, 1, width, 1, -1),
    monotonic_score(board, height, 1, -1, 1),
    monotonic_score(board, height, width, -1, -1)
  )
  return empty * 100 + smooth * 3 + monotonic + corner * 10
end

function M._expected_spawn_score(board)
  local width, height = dimensions(board)
  local empty = 0
  for r = 1, height do
    for c = 1, width do
      if board[r][c] == 0 then empty = empty + 1 end
    end
  end
  if empty == 0 then return heuristic(board) end

  local total = 0
  for r = 1, height do
    for c = 1, width do
      if board[r][c] == 0 then
        local spawned = board_mod.copy_board(board)
        for _, spawn in ipairs(board_mod.SPAWN_DISTRIBUTION) do
          spawned[r][c] = spawn.value
          local score = heuristic(spawned)
          if empty == 1 and not board_mod.any_move_possible(spawned) then
            score = score - LOSS_PENALTY
          end
          total = total + spawn.probability * score
        end
      end
    end
  end
  return total / empty
end

function M.find_best_move(board)
  local best_move, best_score
  for _, direction in ipairs(directions) do
    local next_board, _, gained, changed = board_mod.move_board(board, direction)
    if changed then
      local score = M._expected_spawn_score(next_board) + gained
      if not best_score or score > best_score then
        best_move, best_score = direction, score
      end
    end
  end
  return best_move
end

return M
