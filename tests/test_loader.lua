local loader = loader or dofile("loader.lua")() --luacheck: read_globals loader

local board = loader("lib/board")
assert(board.BOARD_SIZE == 4)
assert(loader("lib/board") == board)

print("loader smoke test passed")
