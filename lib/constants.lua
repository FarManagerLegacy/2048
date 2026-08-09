-- Pure numeric/tuning constants.
local M = {}

-- Game rules: these values define the board contract and spawn behavior.
M.BOARD_SIZE = 4
M.WIN_VALUE = 2048
M.SPAWN_FOUR_PROBABILITY = 0.1
-- Shared board geometry defaults. geometry.lua derives cell/gap dimensions.
M.GEOMETRY_CHAR_ASPECT = 2.6
M.GEOMETRY_UNIT = 3

M.ANIM_FRAMES = 7
M.ANIM_FRAME_DELAY = 0.016
M.SLIDE_DURATION_SECONDS = 0.250
M.HALF_STEP_ANIMATION = true
M.MERGE_POP_FRAMES = 6
M.MERGE_POP_DELAY = 0.02
M.SPAWN_FADE_FRAMES = 4
M.SPAWN_FADE_DELAY = 0.016
M.UNDO_HISTORY_LIMIT = 50
M.STATUS_EFFECT_INTERVAL_SECONDS = 0.10

return M
