local constants = loader("lib/constants")
local solver = loader("lib/ai-" .. constants.AI_SOLVER)
local M = setmetatable({}, { __index = solver })

function M.find_best_move(board, profile, clock)
  if constants.AI_SOLVER == "greedy" then return solver.find_best_move(board) end
  if type(profile) == "number" then return solver.find_best_move(board, profile, clock) end
  profile = profile or constants.AI_BEST_MOVE
  return solver.find_best_move(board, profile.max_depth, profile.budget_ms, nil, nil, clock)
end

return M
