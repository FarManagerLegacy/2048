-- Shared game state and commands used by both the console and FAR frontends.
-- This module owns game rules around a move (history, score, time and status),
-- while frontends remain responsible for input, rendering and animation.
local board_mod = loader("lib/board")
local color = loader("lib/color")
local constants = loader("lib/constants")

local M = {}
local Session = {}
Session.__index = Session

local function default_new_game(spawn_tile)
  local board = board_mod.new_empty_board()
  spawn_tile(board)
  spawn_tile(board)
  return board
end

local function copy_history_entry(entry)
  return {
    board = board_mod.copy_board(entry.board),
    score = entry.score,
    moves_count = entry.moves_count,
    elapsed_seconds = entry.elapsed_seconds,
    status = entry.status,
    paused = entry.paused,
  }
end

local function normalize_palette(name)
  return color.PALETTES[name] and name or "classic"
end

function M.new(options)
  options = options or {}
  local clock = options.clock or os.clock
  local spawn_tile = options.spawn_tile or board_mod.spawn_tile
  local saved = options.state
  local board = saved and board_mod.copy_board(saved.board) or default_new_game(spawn_tile)

  local self = setmetatable({
    board = board,
    score = saved and (saved.score or 0) or 0,
    best = saved and (saved.best or 0) or 0,
    moves_count = saved and (saved.moves_count or 0) or 0,
    elapsed_seconds = saved and (saved.elapsed_seconds or 0) or 0,
    status = board_mod.compute_status(board),
    palette = normalize_palette(saved and saved.palette),
    history = {},
    paused = false,
    time_segment_start = clock(),
    clock = clock,
    spawn_tile = spawn_tile,
    new_game = options.new_game,
    pending_score = 0,
  }, Session)

  if options.history then
    for _, entry in ipairs(options.history) do
      self.history[#self.history + 1] = copy_history_entry(entry)
    end
  end
  return self
end

function Session:_snapshot_for_history()
  return {
    board = board_mod.copy_board(self.board),
    score = self.score,
    moves_count = self.moves_count,
    elapsed_seconds = self:current_elapsed(),
    status = self.status,
    paused = self.paused,
  }
end

function Session:_push_history()
  self.history[#self.history + 1] = self:_snapshot_for_history()
  if #self.history > constants.UNDO_HISTORY_LIMIT then
    table.remove(self.history, 1)
  end
end

function Session:current_elapsed()
  if self.paused or not self.time_segment_start then
    return self.elapsed_seconds
  end
  return self.elapsed_seconds + (self.clock() - self.time_segment_start)
end

function Session:freeze_time()
  self.elapsed_seconds = self:current_elapsed()
  self.time_segment_start = nil
  return self.elapsed_seconds
end

function Session:resume_time()
  if self.status == "" and not self.paused then
    self.time_segment_start = self.clock()
  end
end

function Session:move(direction)
  if self.paused or self.status ~= "" or self.pending_score > 0 then
    return { changed = false, reason = "inactive" }
  end

  local new_board, moves, gained, changed = board_mod.move_board(self.board, direction)
  if not changed then
    return { changed = false, reason = "unchanged" }
  end

  self:_push_history()
  local spawned_board = board_mod.copy_board(new_board)
  local spawned = self.spawn_tile(spawned_board)

  self.board = spawned_board
  self.pending_score = gained
  self.moves_count = self.moves_count + 1
  self.status = board_mod.compute_status(self.board)
  if self.status ~= "" then
    self:freeze_time()
  end

  return {
    changed = true,
    new_board = new_board,
    spawned_board = spawned_board,
    spawned = spawned,
    moves = moves,
    gained = gained,
    status = self.status,
  }
end

function Session:settle_score()
  local gained = self.pending_score
  if gained > 0 then
    self.score = self.score + gained
    self.pending_score = 0
  end
  return gained
end

function Session:has_pending_score()
  return self.pending_score > 0
end

function Session:restart()
  if self:has_pending_score() then return false end
  self:_push_history()
  self.best = math.max(self.best, self.score)
  self.board = self.new_game and self.new_game() or default_new_game(self.spawn_tile)
  self.score = 0
  self.pending_score = 0
  self.moves_count = 0
  self.elapsed_seconds = 0
  self.status = board_mod.compute_status(self.board)
  self.paused = false
  self.time_segment_start = self.clock()
end

function Session:undo()
  if self:has_pending_score() then return false end
  local entry = table.remove(self.history)
  if not entry then return false end

  self.board = board_mod.copy_board(entry.board)
  self.score = entry.score
  self.pending_score = 0
  self.moves_count = entry.moves_count
  self.elapsed_seconds = entry.elapsed_seconds
  self.status = board_mod.compute_status(self.board)
  self.paused = entry.paused or false
  self.time_segment_start = nil
  if self.status == "" and not self.paused then
    self.time_segment_start = self.clock()
  end
  return true
end

function Session:set_paused(paused)
  paused = not not paused
  if self.paused == paused then return end
  if paused then
    self:freeze_time()
    self.paused = true
  else
    self.paused = false
    self:resume_time()
  end
end

function Session:cycle_palette(step)
  self.palette = color.cycle_palette(self.palette, step)
  return self.palette
end

function Session:snapshot()
  return {
    board = board_mod.copy_board(self.board),
    score = self.score,
    best = math.max(self.best, self.score),
    moves_count = self.moves_count,
    status = self.status,
    palette = self.palette,
    elapsed_seconds = self:current_elapsed(),
  }
end

function Session:can_undo()
  return #self.history > 0
end

M.Session = Session
return M
