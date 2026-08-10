local loader = loader or dofile("loader.lua")() --luacheck: read_globals loader

-- loader("missing/commented-module")
local board = loader("lib/board") -- active import with inline comment
local constants = loader("lib/constants")
assert(constants.BOARD_WIDTH == 4 and constants.BOARD_HEIGHT == 4)
assert(board.BOARD_SIZE == nil)
assert(loader("lib/board") == board)

print("loader smoke test passed")
