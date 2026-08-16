-- Pure numeric/tuning constants.
local M = {}

-- Game rules: these values define the board contract and spawn behavior.
M.BOARD_SIZE = 4
M.BOARD_WIDTH = M.BOARD_SIZE
M.BOARD_HEIGHT = M.BOARD_SIZE
M.WIN_INDEX = 11
M.SPAWN_FOUR_PROBABILITY = 0.1

M.AUTO_PLAY_MIN_MOVE_DELAY = 0.500
--M.SKIP_ANIMATIONS = true

-- Shared board geometry defaults. geometry.lua derives cell/gap dimensions.
M.FONT_ASPECT_CORRECTION = 1.3
M.TILE_ASPECT = 1
M.CHAR_ASPECT = 2 * M.TILE_ASPECT * M.FONT_ASPECT_CORRECTION
M.GEOMETRY_UNIT = 3

M.ANIM_FRAME_DELAY = 0.016
M.SLIDE_DURATION_PER_CELL = 0.080
-- Slide easing power: 1 = linear, 2 = quadratic, 3 = cubic; higher values
-- make the ease-out start faster and brake harder. Shared by both axes.
M.ANIM_EASE_POWER = 3
-- Master switch for half-block static rendering and vertical animation.
M.USE_HALF_BLOCKS = true
-- Master switch for drawing empty tile backgrounds.
M.DRAW_EMPTY_TILES = true
M.MERGE_POP_FRAMES = 6
M.MERGE_POP_DELAY = 0.02
M.SPAWN_FADE_FRAMES = 4
M.SPAWN_FADE_DELAY = 0.016
M.UNDO_HISTORY_LIMIT = 50
M.STATUS_EFFECT_INTERVAL_SECONDS = 0.10
M.VICTORY_EFFECT_SECONDS = 5
M.VICTORY_EFFECT_PHASE_SECONDS = math.pi / 2

return M
