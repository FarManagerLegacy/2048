-- FAR backend tests using fake FAR globals and an in-memory buffer.
local loader = dofile("loader.lua")()

local T = loader("tests/test_runner")

local created_width, created_height
far = { --luacheck: allow_defined
  CreateUserControl = function(width, height)
    created_width, created_height = width, height
    return {}
  end,
}
F = { KEY_EVENT = 1 } --luacheck: allow_defined

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
    local tile_idx = geometry.GAP_Y * geometry.BOARD_W + geometry.GAP_X + 1
    T.ok(buffer[tile_idx].Attributes.BackgroundColor
      ~= buffer[1].Attributes.BackgroundColor)
  end)

  T.it("converts shared RGB colors to Windows COLORREF", function()
    T.eq(backend._rgb_to_farcolor({ 0x11, 0x22, 0x33 }), 0x332211)
  end)

  T.it("maps key-down arrow records and ignores other records", function()
    T.eq(backend.map_input_record({
      EventType = F.KEY_EVENT, KeyDown = true, VirtualKeyCode = 0x25,
    }), "left")
    T.eq(backend.map_input_record({
      EventType = F.KEY_EVENT, KeyDown = false, VirtualKeyCode = 0x25,
    }), nil)
    T.eq(backend.map_input_record({
      EventType = 99, KeyDown = true, VirtualKeyCode = 0x25,
    }), nil)
  end)
end)

T.summary_and_exit()
