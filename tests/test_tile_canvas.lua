-- Direct tests for the shared platform-neutral tile rasterizer.
local loader = dofile("loader.lua")()

local T = loader("tests/test_runner")
local canvas = loader("lib/tile_canvas")
local color = loader("lib/color")
local geometry = loader("lib/geometry")

T.describe("tile_canvas", function()
  T.it("creates and fills a board-sized cell buffer", function()
    local empty = color.empty_color("classic")
    local buf = canvas.new_buffer(empty)
    canvas.fill_empty_cells(buf, empty)
    T.eq(#buf, geometry.BOARD_H)
    T.eq(#buf[1], geometry.BOARD_W)
    T.eq(buf[1][1][3], empty)
  end)

  T.it("draws a tile and centers its value", function()
    local empty = color.empty_color("classic")
    local buf = canvas.new_buffer(empty)
    canvas.fill_empty_cells(buf, empty)
    canvas.draw_tile(buf, { row = 0, col = 0, value = 2 }, empty, "classic")

    local text_row = geometry.GAP_Y + math.floor(geometry.CELL_H / 2) + 1
    local text_col = geometry.GAP_X
      + math.floor((geometry.CELL_W - 1) / 2) + 1
    T.eq(buf[text_row][text_col][1], "2")
    T.eq(buf[text_row][text_col][3], color.tile_color(2, "classic"))
  end)

  T.it("rasterizes empty cells and tiles with palette colors", function()
    local empty = color.empty_color("classic")
    local buf = canvas.rasterize({ { row = 0, col = 0, value = 2 } }, {
      palette = "classic",
    })
    T.eq(buf[1][1][3], empty)
    local text_row = geometry.GAP_Y + math.floor(geometry.CELL_H / 2) + 1
    local text_col = geometry.GAP_X
      + math.floor((geometry.CELL_W - 1) / 2) + 1
    T.eq(buf[text_row][text_col][1], "2")
    T.eq(buf[text_row][text_col][3], color.tile_color(2, "classic"))
  end)

  T.it("rasterizes fade against the tinted empty background", function()
    local tint = { 100, 110, 120 }
    local tile_bg = color.tile_color(2, "classic")
    local buf = canvas.rasterize({ { row = 0, col = 0, value = 2 } }, {
      palette = "classic",
      board_tint = tint,
      fade = 0.5,
    })
    T.eq(buf[1][1][3], { 50, 55, 60 })
    local tile_x = geometry.GAP_X + 1
    local tile_y = geometry.GAP_Y + math.floor(geometry.CELL_H / 2) + 1
    T.eq(buf[tile_y][tile_x][3], {
      math.floor(tile_bg[1] / 2),
      math.floor(tile_bg[2] / 2),
      math.floor(tile_bg[3] / 2),
    })
  end)
end)

T.summary_and_exit()
