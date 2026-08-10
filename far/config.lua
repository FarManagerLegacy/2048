local M = {}
local constants = loader("lib/constants")

-- Keep the FAR driver on the same one-frame cadence as console/animation.lua.
-- The interval is changed per FSM phase below because merge-pop intentionally
-- has a different delay from slide and spawn-fade.
M.FRAMES_PER_TICK = 1
M.DEBUG = false
M.TIMER_INTERVAL_MS = math.floor(constants.ANIM_FRAME_DELAY * 1000 + 0.5)
M.PHASE_DELAYS = {
  constants.ANIM_FRAME_DELAY,
  constants.MERGE_POP_DELAY,
  constants.SPAWN_FADE_DELAY,
}
M.CLOCK_INTERVAL_MS = 1000
M.STATUS_EFFECT_INTERVAL_MS = math.floor(constants.STATUS_EFFECT_INTERVAL_SECONDS * 1000 + 0.5)
M.DIALOG_TITLE = "2048"
M.INNER_MARGIN_X = 1
M.INNER_MARGIN_Y = 0
M.OUTER_MARGIN_X = 3
M.OUTER_MARGIN_Y = 1
M.STATS_LABEL_WIDTH = 12
M.STATS_VALUE_WIDTH = 10
M.BUTTON_WIDTH = 12

return M
