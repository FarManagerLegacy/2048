-- FAR backend tests using fake FAR globals and an in-memory buffer.
local loader = dofile("loader.lua")()

local T = loader("tests/test_runner")
local constants = loader("lib/constants")
-- Fixture config: these tests cover this explicit baseline, not defaults.
constants.GEOMETRY_UNIT = 3
constants.USE_HALF_BLOCKS = true

local created_width, created_height
far = { --luacheck: allow_defined
  Flags = { FCF_FG_BOLD = 8 },
  CreateUserControl = function(width, height)
    created_width, created_height = width, height
    return {}
  end,
}
local backend = loader("far/backend")
local geometry = loader("lib/geometry")

T.describe("far.backend", function()
  T.it("creates a buffer with the configured board dimensions", function()
    local buffer = backend.create_buffer()
    T.eq(created_width, geometry.BOARD_W)
    T.eq(created_height, geometry.BOARD_H)
    T.ok(type(buffer) == "table")
  end)

  T.it("draws logical tiles into the FAR buffer", function()
    local buffer = backend.create_buffer()
    backend.draw_to_far_buffer(buffer, {
      tiles = { { row = 0, col = 0, value = 2 } },
      palette = "classic",
    })
    T.ok(buffer[1] ~= nil)
    T.ok(buffer[1].Attributes ~= nil)
    local found_tile = false
    for _, cell in pairs(buffer) do
      if cell.Char == "2" then
        found_tile = true
        T.ok(cell.Attributes.BackgroundColor ~= buffer[1].Attributes.BackgroundColor)
        T.eq(cell.Attributes.Flags, far.Flags.FCF_FG_BOLD)
        break
      end
    end
    T.ok(found_tile, "expected the tile digit in the FAR buffer")
  end)

  T.it("converts shared RGB colors to Windows COLORREF", function()
    T.eq(backend._rgb_to_farcolor({ 0x11, 0x22, 0x33 }), 0x332211)
  end)

end)

T.summary_and_exit()
