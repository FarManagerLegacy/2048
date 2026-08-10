local loader = loader or dofile("loader.lua")() --luacheck: read_globals loader

-- loader("missing/commented-module")
local board = loader("lib/board") -- active import with inline comment
assert(board.BOARD_SIZE == 4)
assert(loader("lib/board") == board)

print("loader smoke test passed")
