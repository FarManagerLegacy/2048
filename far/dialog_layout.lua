-- FAR dialog geometry and item construction. No game state lives here.
local geometry = loader("lib/geometry")
local config = loader("far/config")

local M = {}

function M.calculate()
  local board_w, board_h = geometry.BOARD_W, geometry.BOARD_H
  local stats_total_width = config.STATS_TOTAL_WIDTH
  local board_x1 = config.OUTER_MARGIN_X + config.INNER_MARGIN_X + 1
  local board_y1 = config.OUTER_MARGIN_Y + config.INNER_MARGIN_Y + 1
  local board_x2 = board_x1 + board_w - 1
  local board_y2 = board_y1 + board_h - 1
  local stats_x1 = board_x2 + config.INNER_MARGIN_X + 2
  local stats_x2 = stats_x1 + stats_total_width - 1
  local doublebox_x1 = config.OUTER_MARGIN_X
  local doublebox_x2 = stats_x2 + config.INNER_MARGIN_X + 1
  local doublebox_y1 = config.OUTER_MARGIN_Y
  local doublebox_y2 = board_y2 + config.INNER_MARGIN_Y + 1

  return {
    unit = geometry.UNIT,
    board_w = board_w, board_h = board_h,
    doublebox_x1 = doublebox_x1, doublebox_x2 = doublebox_x2,
    doublebox_y1 = doublebox_y1, doublebox_y2 = doublebox_y2,
    doublebox_w = doublebox_x2 - doublebox_x1 + 1,
    doublebox_h = doublebox_y2 - doublebox_y1 + 1,
    dialog_w = doublebox_x2 + config.OUTER_MARGIN_X + 1,
    dialog_h = doublebox_y2 + config.OUTER_MARGIN_Y + 1,
    board_x1 = board_x1, board_y1 = board_y1,
    board_x2 = board_x2, board_y2 = board_y2,
    stats_x1 = stats_x1, stats_x2 = stats_x2,
    stats_total_width = stats_total_width,
  }
end

function M.fit_to_height(height, preferred_unit)
  preferred_unit = preferred_unit or geometry.UNIT
  local maximum_unit = 2
  for unit = 2, height do
    geometry.set_unit(unit)
    local geom = M.calculate()
    if geom.dialog_h > height then break end
    maximum_unit = unit
  end
  geometry.set_unit(math.min(math.max(2, preferred_unit), maximum_unit))
  return M.calculate()
end

function M.build_items(F, geom, far_buffer)
  local items, ids = {}, {}
  local function add_item(name, item)
    items[#items + 1] = item
    ids[name] = #items
  end

  add_item("doublebox", {
    "DI_DOUBLEBOX", geom.doublebox_x1, geom.doublebox_y1,
    geom.doublebox_x2, geom.doublebox_y2, 0, 0, 0, 0, "2048",
  })

  add_item("time", {
    "DI_TEXT", geom.doublebox_x2 - 6, geom.doublebox_y1,
    geom.doublebox_x2 - 6, geom.doublebox_y1, 0, 0, 0, 0, "",
  })
  add_item("pause_button", {
    "DI_BUTTON", geom.doublebox_x2 - 4, geom.doublebox_y1,
    geom.doublebox_x2 - 2, geom.doublebox_y1,
    0, 0, 0, F.DIF_BTNNOCLOSE + F.DIF_NOFOCUS + F.DIF_NOBRACKETS, " ▷ ",
  })

  local footer_y = geom.doublebox_y2
  local score_x = geom.doublebox_x1 + 2
  local best_x = geom.board_x2 + 2
  add_item("score_label", { "DI_TEXT", score_x, footer_y, best_x - 1, footer_y, 0, 0, 0, 0, "" })
  add_item("score", { "DI_TEXT", score_x + 7, footer_y, best_x - 2, footer_y, 0, 0, 0, 0, "" })
  add_item("best_label", { "DI_TEXT", best_x, footer_y, geom.doublebox_x2 - 1, footer_y, 0, 0, 0, 0, "" })
  add_item("best", { "DI_TEXT", best_x + 6, footer_y, geom.doublebox_x2 - 2, footer_y, 0, 0, 0, 0, "" })

  add_item("usercontrol", {
    "DI_USERCONTROL", geom.board_x1, geom.board_y1,
    geom.board_x2, geom.board_y2, far_buffer, 0, F.DIF_FOCUS + (F.DIF_HOMEITEM or 0), 0, "",
  })

  local stats_y = geom.board_y1
  add_item("moves_label", {
    "DI_TEXT", geom.stats_x1, stats_y,
    geom.stats_x1 + 5, stats_y, 0, 0, 0, 0, "Moves:",
  })
  add_item("undo_button", {
    "DI_BUTTON", geom.stats_x1 + 6, stats_y,
    geom.stats_x1 + 9, stats_y,
    0, 0, 0, F.DIF_BTNNOCLOSE + F.DIF_NOBRACKETS, " &↺ ",
  })
  add_item("moves", {
    "DI_TEXT", geom.stats_x1 + 9, stats_y,
    geom.stats_x1 + geom.stats_total_width - 1, stats_y, 0, 0, 0, 0, "",
  })

  local status_y = stats_y
  add_item("status", {
    "DI_TEXT", geom.stats_x1, status_y,
    geom.stats_x1 + geom.stats_total_width - 1, status_y, 0, 0, 0, 0, "",
  })
  add_item("new_button", {
    "DI_BUTTON", geom.stats_x1, status_y + 1,
    geom.stats_x1 + 2, status_y + 1,
    0, 0, 0, F.DIF_BTNNOCLOSE, "&New",
  })

  local switch_y = geom.board_y2
  add_item("palette", {
    "DI_TEXT", geom.stats_x1 + 1, switch_y,
    geom.stats_x1 + geom.stats_total_width - 2, switch_y, 0, 0, 0, 0, "",
  })
  add_item("palette_prev_button", {
    "DI_BUTTON", geom.stats_x1, switch_y,
    geom.stats_x1, switch_y,
    0, 0, 0, F.DIF_BTNNOCLOSE + F.DIF_NOBRACKETS, "&<",
  })
  add_item("palette_label", {
    "DI_TEXT", geom.stats_x1, switch_y - 1,
    geom.stats_x1 + geom.stats_total_width - 1, switch_y - 1, 0, 0, 0, 0, "&Palette:",
  })
  add_item("palette_next_button", {
    "DI_BUTTON", geom.stats_x1 + geom.stats_total_width - 1, switch_y,
    geom.stats_x1 + geom.stats_total_width - 1, switch_y,
    0, 0, 0, F.DIF_BTNNOCLOSE + F.DIF_NOBRACKETS, "&>",
  })
  return items, ids
end

return M
