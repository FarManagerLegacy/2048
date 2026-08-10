-- Frame-advancing state machines for slide/merge/spawn animations.
--
-- Unlike console/animation.lua (which owns a blocking loop calling render+sleep
-- itself -- fine for the console backend, which owns its own main loop),
-- these state machines do neither rendering nor sleeping. They only compute
-- "what should the tile list look like at frame N" and let the CALLER
-- decide when to advance and when/how to render.
--
-- This split exists specifically for platforms where WE do not own the
-- main loop -- e.g. FAR Manager, where far.DialogRun() owns it and our
-- code only runs reactively (DN_DRAWDLGITEM, a far.Timer callback, or
-- DN_INPUT). The FAR frontend configures how many frames one external
-- "tick" advances.

local color = loader("lib/color")
local util = loader("lib/util")
local constants = loader("lib/constants")
local geometry = loader("lib/geometry")

local BOARD_SIZE = constants.BOARD_SIZE
local ROW_STEPS_PER_CELL = geometry.ROW_STRIDE_Y

local M = {}

local function ease_out_cubic(t)
  return 1 - (1 - t) ^ constants.ANIM_EASE_POWER
end
M.ease_out_cubic = ease_out_cubic

function M.next_frame_delay(deadline, now, remaining_steps)
  if remaining_steps <= 0 then return 0 end
  return math.max(0, (deadline - now) / remaining_steps)
end

-- ---------------------------------------------------------------------
-- Slide phase state machine
-- ---------------------------------------------------------------------

local SlideFSM = {}
SlideFSM.__index = SlideFSM

-- moves: array of {fr, fc, tr, tc, value, merged} with 1-based board coords.
function M.new_slide(moves)
  local max_vertical_distance = 0
  for _, mv in ipairs(moves) do
    max_vertical_distance = math.max(max_vertical_distance, math.abs(mv.tr - mv.fr))
  end
  local vertical_steps = constants.USE_HALF_BLOCKS and ROW_STEPS_PER_CELL * 2 or ROW_STEPS_PER_CELL
  return setmetatable({
    moves = moves,
    step = 0,
    total_steps = max_vertical_distance > 0 and max_vertical_distance * vertical_steps or constants.ANIM_FRAMES,
    done = (#moves == 0),
  }, SlideFSM)
end

-- Advance by n frames (default 1). Returns self for chaining.
function SlideFSM:advance(n)
  n = n or 1
  if self.done then return self end
  self.step = math.min(self.total_steps, self.step + n)
  if self.step >= self.total_steps then
    self.done = true
  end
  return self
end

-- Returns the tile list to render for the current frame (0-based row/col).
function SlideFSM:tiles()
  local out = {}
  local t = ease_out_cubic(self.step / self.total_steps)
  for _, mv in ipairs(self.moves) do
    local row = (mv.fr - 1) + ((mv.tr - 1) - (mv.fr - 1)) * t
    local col = (mv.fc - 1) + ((mv.tc - 1) - (mv.fc - 1)) * t
    out[#out + 1] = { row = row, col = col, value = mv.value }
  end
  return out
end

function SlideFSM:is_done()
  return self.done
end

-- ---------------------------------------------------------------------
-- Merge-pop phase state machine
-- ---------------------------------------------------------------------

local MergePopFSM = {}
MergePopFSM.__index = MergePopFSM

local FLASH_COLOR = { 255, 255, 255 }

-- board: post-move board (1-based). moves: same shape as above.
function M.new_merge_pop(board, moves, palette)
  local merge_targets = {}
  local merge_target_coords = {}
  for _, mv in ipairs(moves) do
    if mv.merged then
      local key = mv.tr .. "," .. mv.tc
      if not merge_targets[key] then
        merge_target_coords[#merge_target_coords + 1] = { mv.tr, mv.tc }
      end
      merge_targets[key] = mv.value
    end
  end

  local static_tiles = {}
  for r = 1, BOARD_SIZE do
    for c = 1, BOARD_SIZE do
      local key = r .. "," .. c
      if board[r][c] ~= 0 and merge_targets[key] == nil then
        static_tiles[#static_tiles + 1] = { row = r - 1, col = c - 1, value = board[r][c] }
      end
    end
  end

  return setmetatable({
    board = board,
    palette = palette,
    merge_targets = merge_targets,
    merge_target_coords = merge_target_coords,
    static_tiles = static_tiles,
    step = 0,
    total_steps = constants.MERGE_POP_FRAMES,
    done = (#merge_target_coords == 0),
  }, MergePopFSM)
end

function MergePopFSM:advance(n)
  n = n or 1
  if self.done then return self end
  self.step = math.min(self.total_steps, self.step + n)
  if self.step >= self.total_steps then
    self.done = true
  end
  return self
end

function MergePopFSM:tiles()
  local t = self.step / self.total_steps
  local bump = math.sin(math.pi * t) * 0.18
  local out = {}
  for _, tile in ipairs(self.static_tiles) do out[#out + 1] = tile end

  for _, rc in ipairs(self.merge_target_coords) do
    local r, c = rc[1], rc[2]
    local old_value = self.merge_targets[r .. "," .. c]
    local new_value = self.board[r][c]
    local old_bg = color.tile_color(old_value, self.palette)
    local new_bg = color.tile_color(new_value, self.palette)
    local bg = util.blend(old_bg, new_bg, t)
    bg = util.lighten(bg, bump)
    local normal_fg = color.tile_text_color(new_value, self.palette)
    local fg = util.blend(FLASH_COLOR, normal_fg, t)
    out[#out + 1] = { row = r - 1, col = c - 1, value = new_value, bg = bg, fg = fg }
  end
  return out
end

function MergePopFSM:is_done()
  return self.done
end

-- ---------------------------------------------------------------------
-- Spawn fade-in phase state machine
-- ---------------------------------------------------------------------

local SpawnFadeFSM = {}
SpawnFadeFSM.__index = SpawnFadeFSM

-- board: post-move+spawn board (1-based). spawned: {r, c, value} (1-based).
function M.new_spawn_fade(board, spawned, palette)
  return setmetatable({
    board = board,
    spawned = spawned,
    palette = palette,
    step = 0,
    total_steps = constants.SPAWN_FADE_FRAMES,
    done = false,
  }, SpawnFadeFSM)
end

function SpawnFadeFSM:advance(n)
  n = n or 1
  if self.done then return self end
  self.step = math.min(self.total_steps, self.step + n)
  if self.step >= self.total_steps then
    self.done = true
  end
  return self
end

function SpawnFadeFSM:tiles()
  local alpha = self.step / self.total_steps
  local sr, sc, sval = self.spawned.r, self.spawned.c, self.spawned.value
  local out = {}
  for r = 1, BOARD_SIZE do
    for c = 1, BOARD_SIZE do
      if self.board[r][c] ~= 0 then
        if r == sr and c == sc then
          out[#out + 1] = { row = r - 1, col = c - 1, value = sval, alpha = alpha }
        else
          out[#out + 1] = { row = r - 1, col = c - 1, value = self.board[r][c] }
        end
      end
    end
  end
  return out
end

function SpawnFadeFSM:is_done()
  return self.done
end

-- ---------------------------------------------------------------------
-- Sequence helper: chain slide -> merge_pop -> spawn_fade as one object,
-- so callers (e.g. the FAR timer handler) can advance a single "move
-- animation" without caring which phase is currently active.
-- ---------------------------------------------------------------------

local MoveAnimation = {}
MoveAnimation.__index = MoveAnimation

-- new_board: board after the move (pre-spawn). moves: from move_board().
-- spawned_board/spawned: board+tile after spawn_tile() was applied.
function M.new_move_animation(new_board, moves, spawned_board, spawned, palette)
  local phases = {}
  phases[#phases + 1] = M.new_slide(moves)
  phases[#phases + 1] = M.new_merge_pop(new_board, moves, palette)
  if spawned then
    phases[#phases + 1] = M.new_spawn_fade(spawned_board, spawned, palette)
  end
  return setmetatable({
    phases = phases,
    phase_idx = 1,
  }, MoveAnimation)
end

-- Advances the currently-active phase by n frames. If that phase
-- finishes mid-advance, does NOT automatically spill remaining frames
-- into the next phase -- keeps frame accounting simple and predictable
-- (one external tick advances at most one phase's worth of progress).
function MoveAnimation:advance(n)
  local phase = self.phases[self.phase_idx]
  if not phase then return self end
  phase:advance(n)
  while phase:is_done() and self.phase_idx < #self.phases do
    self.phase_idx = self.phase_idx + 1
    phase = self.phases[self.phase_idx]
  end
  return self
end

function MoveAnimation:tiles()
  local phase = self.phases[self.phase_idx]
  if not phase then return {} end
  return phase:tiles()
end

function MoveAnimation:is_done()
  local last = self.phases[#self.phases]
  return self.phase_idx == #self.phases and last:is_done()
end

return M
