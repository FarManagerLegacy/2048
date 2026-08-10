-- Direct tests for the shared platform-neutral tile rasterizer.
local loader = dofile("loader.lua")()

local T = loader("tests/test_runner")
local constants = loader("lib/constants")
-- Fixture config: these tests cover this explicit baseline, not defaults.
constants.GEOMETRY_UNIT = 3
constants.USE_HALF_BLOCKS = true
local canvas = loader("lib/tile_canvas")
local color = loader("lib/color")
local geometry = loader("lib/geometry")
local util = loader("lib/util")

local function load_geometry_case(unit, use_half_blocks)
  local fresh_loader = dofile("loader.lua")()
  local case_constants = fresh_loader("lib/constants")
  case_constants.GEOMETRY_UNIT = unit
  case_constants.USE_HALF_BLOCKS = use_half_blocks
  return fresh_loader("lib/tile_canvas"), fresh_loader("lib/geometry"), fresh_loader("lib/color")
end

T.describe("tile_canvas", function()
  local function halves(cell)
    if cell[1] == "▀" then return cell[2], cell[3] end
    if cell[1] == "▄" then return cell[3], cell[2] end
    return cell[3], cell[3]
  end

  T.it("keeps even cell heights and computes their vertical layouts", function()
    local _, cell_h = geometry.compute_cell_dimensions(2, 2.25)
    T.eq(cell_h, 2)

    local inset, stride = geometry.compute_vertical_layout(2, 0, true)
    T.eq(inset, 0.5)
    T.eq(stride, 2)

    inset, stride = geometry.compute_vertical_layout(2, 0, false)
    T.eq(inset, 0)
    T.eq(stride, 2)
  end)

  T.it("keeps a visible vertical gap at geometry size four", function()
    local _, gap_y = geometry.compute_gaps(4)
    T.eq(gap_y, 1)
  end)

  T.it("tests rendering independently across geometry and flag settings", function()
    for _, unit in ipairs({ 2, 3, 4, 5 }) do
      for _, use_half_blocks in ipairs({ true, false }) do
        local case_canvas, case_geometry, case_color = load_geometry_case(unit, use_half_blocks)
        local buf = case_canvas.rasterize({ { row = 0, col = 0, value = 2 } }, { palette = "classic" })
        T.eq(case_geometry.CELL_H, unit)
        T.eq(#buf, case_geometry.BOARD_H)
        local found_text = false
        for _, row in ipairs(buf) do
          for _, cell in ipairs(row) do
            if cell[1] == "2" then found_text = true end
            if not use_half_blocks then
              T.ok(cell[1] ~= "▀" and cell[1] ~= "▄")
            end
          end
        end
        T.ok(found_text, "expected tile text for geometry unit " .. unit)
        T.eq(case_color.tile_color(2, "classic"), { 238, 228, 218 })
      end
    end
  end)

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

    local text_row = math.floor(geometry.OUTER_INSET_Y + math.floor(geometry.CELL_H / 2)) + 1
    local text_col = geometry.GAP_X
      + math.floor((geometry.CELL_W - 1) / 2) + 1
    T.eq(buf[text_row][text_col][1], "2")
    T.eq(buf[text_row][text_col][3], color.tile_color(2, "classic"))
    T.ok(buf[text_row][text_col][4], "tile digits should be bold")
  end)

  T.it("rasterizes empty cells and tiles with palette colors", function()
    local empty = color.empty_color("classic")
    local buf = canvas.rasterize({ { row = 0, col = 0, value = 2 } }, {
      palette = "classic",
    })
    T.eq(buf[1][1][3], empty)
    local text_row = math.floor(geometry.OUTER_INSET_Y + math.floor(geometry.CELL_H / 2)) + 1
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
    local tile_y = math.floor(geometry.OUTER_INSET_Y + math.floor(geometry.CELL_H / 2)) + 1
    T.eq(buf[tile_y][tile_x][3], {
      math.floor(tile_bg[1] / 2),
      math.floor(tile_bg[2] / 2),
      math.floor(tile_bg[3] / 2),
    })
  end)

  T.it("renders a half-row offset tile through both halves of its edge cells", function()
    local empty = color.empty_color("classic")
    local tile = color.tile_color(2, "classic")
    local buf = canvas.rasterize({ { row = 0.125, col = 0, value = 2 } }, { palette = "classic" })
    local x = geometry.GAP_X + 1
    local y = geometry.OUTER_INSET_Y + 0.125 * geometry.ROW_STRIDE_Y
    local start_half = util.round(2 * y)
    local first_row = math.floor(start_half / 2) + 1
    local top, bottom = halves(buf[first_row][x])
    local first_cell_start = (first_row - 1) * 2
    local end_half = start_half + geometry.CELL_H * 2 - 1
    T.eq(top, first_cell_start >= start_half and first_cell_start <= end_half and tile or empty)
    T.eq(bottom, first_cell_start + 1 >= start_half and first_cell_start + 1 <= end_half and tile or empty)
    local last_row = math.floor(end_half / 2) + 1
    top, bottom = halves(buf[last_row][x])
    local last_cell_start = (last_row - 1) * 2
    T.eq(top, last_cell_start >= start_half and last_cell_start <= end_half and tile or empty)
    T.eq(bottom, last_cell_start + 1 >= start_half and last_cell_start + 1 <= end_half and tile or empty)
  end)

  T.it("uses whole rows when half blocks are disabled", function()
    local old_use_half_blocks = constants.USE_HALF_BLOCKS
    constants.USE_HALF_BLOCKS = false
    local buf = canvas.rasterize({ { row = 0, col = 0, value = 2 } }, { palette = "classic" })
    constants.USE_HALF_BLOCKS = old_use_half_blocks

    local text_row = util.round(geometry.OUTER_INSET_Y) + math.floor(geometry.CELL_H / 2) + 1
    local text_col = geometry.GAP_X + math.floor((geometry.CELL_W - 1) / 2) + 1
    T.eq(buf[text_row][text_col][1], "2")
    for _, row in ipairs(buf) do
      for _, cell in ipairs(row) do
        T.ok(cell[1] ~= "▀" and cell[1] ~= "▄", "whole-row rendering must not emit half blocks")
      end
    end
  end)

  T.it("keeps adjacent half-row tiles continuous and retains their text colors", function()
    local empty = color.empty_color("classic")
    local tile = color.tile_color(2, "classic")
    local buf = canvas.rasterize({
      { row = 0.5, col = 0, value = 2 },
      { row = 1.25, col = 0, value = 2 },
    }, { palette = "classic" })
    local x = geometry.GAP_X + 1
    local first_start = util.round(2 * (geometry.OUTER_INSET_Y + 0.5 * geometry.ROW_STRIDE_Y))
    local second_end = util.round(2 * (geometry.OUTER_INSET_Y + 1.25 * geometry.ROW_STRIDE_Y))
      + geometry.CELL_H * 2 - 1
    for half = first_start, second_end do
      local row = math.floor(half / 2) + 1
      local top, bottom = halves(buf[row][x])
      T.eq(half % 2 == 0 and top or bottom, tile)
    end
    local text_col = geometry.GAP_X + math.floor((geometry.CELL_W - 1) / 2) + 1
    local text_row = math.floor((
      util.round(2 * (geometry.OUTER_INSET_Y + 0.5 * geometry.ROW_STRIDE_Y))
      + geometry.CELL_H
    ) / 2) + 1
    T.eq(buf[text_row][text_col][1], "2")
    T.eq(buf[text_row][text_col][2], color.text_color(tile))
    T.eq(buf[text_row][text_col][3], tile)
    T.eq(buf[1][1][3], empty)
  end)
end)

T.summary_and_exit()
