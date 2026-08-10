-- FAR Manager rendering + input backend for DI_USERCONTROL.
--
-- This module is the FAR counterpart to console/render.lua + console/winapi.lua (which
-- target a Windows console via ANSI escapes + msvcrt). It draws into a
-- far.CreateUserControl() buffer instead of stdout, and reads FAR's
-- INPUT_RECORD tables instead of msvcrt._getch().
--
-- Requires the global `far` and `F` tables that LuaMacro injects into
-- every macro's environment -- this file only runs inside FAR, not under
-- plain luajit.exe.
-- luacheck: globals far

local geometry = loader("lib/geometry")
local canvas = loader("lib/tile_canvas")

local M = {}

local BOARD_W, BOARD_H = geometry.BOARD_W, geometry.BOARD_H

-- ---------------------------------------------------------------------
-- Buffer creation / color conversion
-- ---------------------------------------------------------------------

-- far.CreateUserControl(width, height) returns a buffer indexable 1..W*H,
-- row-major, one CHAR_INFO-like cell per character position -- the exact
-- same logical shape as render.lua's `buf[y][x]` 2D table, just flattened
-- and 1-indexed differently. We keep our own 2D Lua table as the "source
-- of truth" and flush it into the FAR buffer on demand, mirroring how
-- render.lua's make_buffer()/render_buffer() split concerns.
function M.create_buffer()
  return far.CreateUserControl(BOARD_W, BOARD_H)
end

-- FAR stores true-color fields as Windows COLORREF values. COLORREF is
-- 0x00BBGGRR, while the shared palette uses { red, green, blue } arrays.
-- Flags=0 keeps the values in true-color mode (no palette reduction).
local function rgb_to_farcolor(c)
  return c[1] + c[2] * 0x100 + c[3] * 0x10000
end
M._rgb_to_farcolor = rgb_to_farcolor

local F = far.Flags
local function far_color_attributes(fg, bg, bold)
  return {
    Flags = bold and F.FCF_FG_BOLD or 0,
    ForegroundColor = rgb_to_farcolor(fg),
    BackgroundColor = rgb_to_farcolor(bg),
  }
end
M._far_color_attributes = far_color_attributes

-- ---------------------------------------------------------------------
-- Drawing: same 2D scratch-buffer approach as render.lua, so tile-layout
-- math (draw_tile positions, cell/gap sizes) is not duplicated -- only
-- the final "blit to the real output" step differs (FAR buffer vs ANSI).
-- ---------------------------------------------------------------------

-- Renders `tiles` (0-based row/col, same shape render.lua/animation_fsm.lua
-- produce) into the FAR buffer object. Call this from DN_DRAWDLGITEM, not
-- from a timer -- FAR owns *when* drawing actually happens; we only own
-- *what* the buffer should contain at that moment.
function M.draw_to_far_buffer(far_buffer, opts)
  local tiles = opts.tiles
  local board_tint = opts.board_tint
  local fade = opts.fade or 0
  local palette = opts.palette
  local buf = canvas.rasterize(tiles, {
    board_tint = board_tint,
    fade = fade,
    palette = palette,
  })

  for y = 1, BOARD_H do
    for x = 1, BOARD_W do
      local ch, fg, bg, bold = buf[y][x][1], buf[y][x][2], buf[y][x][3], buf[y][x][4]
      local idx = (y - 1) * BOARD_W + x
      far_buffer[idx] = {
        Char = ch,
        Attributes = far_color_attributes(fg or bg, bg, bold),
      }
    end
  end
end

return M
