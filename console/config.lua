local M = {}
local constants = loader("lib/constants")

M.END_SCREEN_TICK = constants.STATUS_EFFECT_INTERVAL_SECONDS
M.IDLE_POLL_DELAY = 0.05

return M
