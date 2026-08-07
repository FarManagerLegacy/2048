-- Blocking console driver for animation_fsm.lua.
-- The FSM owns frame calculation; this module only advances it and renders.
local animation_fsm = loader("lib/animation_fsm")
local render = loader("console/render")
local winapi = loader("console/winapi")
local constants = loader("lib/constants")

local M = {}

local function play_phase(phase, stats, palette, delay)
  while not phase:is_done() do
    phase:advance(1)
    local tiles = phase:tiles()
    render.render_frame({
      tiles = tiles,
      score = stats.score,
      best = stats.best,
      moves_count = stats.moves_count,
      elapsed_seconds = stats.elapsed_seconds,
      palette = palette,
    })
    winapi.sleep(delay)
  end
end

function M.play_move(new_board, moves, spawned_board, spawned, stats, palette)
  local animation = animation_fsm.new_move_animation(
    new_board, moves, spawned_board, spawned, palette
  )
  local delays = {
    constants.ANIM_FRAME_DELAY,
    constants.MERGE_POP_DELAY,
    constants.SPAWN_FADE_DELAY,
  }
  while not animation:is_done() do
    local phase = animation.phases[animation.phase_idx]
    play_phase(phase, stats, palette, delays[animation.phase_idx])
    animation:advance(0)
  end
end

function M.animate_slide(moves, score, best, moves_count, elapsed_seconds, palette)
  local phase = animation_fsm.new_slide(moves)
  play_phase(phase, {
    score = score, best = best, moves_count = moves_count,
    elapsed_seconds = elapsed_seconds,
  }, palette, constants.ANIM_FRAME_DELAY)
end

function M.animate_merge_pop(board, moves, score, best, moves_count, elapsed_seconds, palette)
  local phase = animation_fsm.new_merge_pop(board, moves, palette)
  play_phase(phase, {
    score = score, best = best, moves_count = moves_count,
    elapsed_seconds = elapsed_seconds,
  }, palette, constants.MERGE_POP_DELAY)
end

function M.animate_spawn_fadein(board, spawned, score, best, moves_count, elapsed_seconds, palette)
  local phase = animation_fsm.new_spawn_fade(board, spawned, palette)
  play_phase(phase, {
    score = score, best = best, moves_count = moves_count,
    elapsed_seconds = elapsed_seconds,
  }, palette, constants.SPAWN_FADE_DELAY)
end

return M
