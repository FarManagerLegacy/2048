-- FAR dialog geometry and item construction. No game state lives here.
local geometry = loader("lib/geometry")
local config = loader("far/config")

local M = {}

function M.calculate()
  local board_w, board_h = geometry.BOARD_W, geometry.BOARD_H
  local stats_label_width = config.STATS_LABEL_WIDTH
  local stats_value_width = config.STATS_VALUE_WIDTH
  local stats_total_width = stats_label_width + stats_value_width
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
    stats_label_width = stats_label_width,
    stats_value_width = stats_value_width,
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
  add_item("usercontrol", {
    "DI_USERCONTROL", geom.board_x1, geom.board_y1,
    geom.board_x2, geom.board_y2, far_buffer, 0, 0, 0, "",
  })

  local stats_y = geom.board_y1
  for index, name in ipairs({ "score", "best", "moves" }) do
    local y = stats_y + index - 1
    add_item(name, {
      "DI_TEXT", geom.stats_x1, y,
      geom.stats_x1 + geom.stats_total_width - 1, y, 0, 0, 0, 0, "",
    })
  end

  local action_y = stats_y + 3
  for index, button in ipairs({ { "undo_button", "&Undo" }, { "new_button", "&New" } }) do
    local y = action_y + index - 1
    add_item(button[1], {
      "DI_BUTTON", geom.stats_x1, y,
    geom.stats_x1 + config.BUTTON_WIDTH - 1, y,
    0, 0, 0, F.DIF_BTNNOCLOSE, button[2],
    })
  end

  local time_y = action_y + 3
  add_item("time", {
    "DI_TEXT", geom.stats_x1, time_y,
    geom.stats_x1 + geom.stats_total_width - 1, time_y, 0, 0, 0, 0, "",
  })
  local pause_y = time_y + 1
  add_item("pause_button", {
    "DI_BUTTON", geom.stats_x1, pause_y,
    geom.stats_x1 + config.BUTTON_WIDTH - 1, pause_y,
    0, 0, 0, F.DIF_BTNNOCLOSE, "&Pause",
  })

  local switch_y = geom.board_y2
  add_item("status", {
    "DI_TEXT", geom.stats_x1, pause_y + 2,
    geom.stats_x1 + geom.stats_total_width - 1, pause_y + 2, 0, 0, 0, 0, "",
  })
  add_item("palette", {
    "DI_TEXT", geom.stats_x1, switch_y - 1,
    geom.stats_x1 + geom.stats_total_width - 1, switch_y - 1, 0, 0, 0, 0, "",
  })
  add_item("switch_button", {
    "DI_BUTTON", geom.stats_x1, switch_y,
    geom.stats_x1 + config.BUTTON_WIDTH - 1, switch_y,
    0, 0, 0, F.DIF_BTNNOCLOSE, "&Switch",
  })
  return items, ids
end

return M
