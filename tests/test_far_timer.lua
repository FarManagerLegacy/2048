local root_loader = dofile("loader.lua")()
local T = root_loader("tests/test_runner")

local clock = 0
local animation_timer
local dialog_proc
local move_directions = {}
local F = {
  DN_INITDIALOG = "init", DN_CONTROLINPUT = "input", DN_KEY = "key",
  DN_DRAWDLGITEM = "draw", DN_BTNCLICK = "click", DN_GOTFOCUS = "focus",
  DN_CTLCOLORDLGITEM = "color", DN_CLOSE = "close",
}

far = { --luacheck: allow_defined
  Flags = F,
  FarClock = function() return clock * 1000000 end,
  Timer = function(_, callback)
    local timer = { Enabled = false, Interval = 0, Close = function() end }
    if not animation_timer then animation_timer = { timer = timer, callback = callback } end
    return timer
  end,
  Dialog = function(_, _, _, _, _, _, _, _, callback)
    local hdlg = { ShowItem = function() end }
    dialog_proc = callback
    callback(hdlg, F.DN_INITDIALOG, 0, nil)
  end,
  SendDlgMessage = function(_, message, item)
    if (message == "DM_SHOWITEM" or message == "DM_REDRAW") and dialog_proc then
      dialog_proc({}, F.DN_DRAWDLGITEM, item, nil)
    end
  end,
  InputRecordToName = function(record) return record.name end,
  KeyToName = function(record) return record.name end,
}
bit64 = { bor = function(a, b) return a + b end } --luacheck: allow_defined

local board = {
  { 2, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 },
}
local config = {
  FRAMES_PER_TICK = 1, TIMER_INTERVAL_MS = 1,
  PHASE_DELAYS = { 0.01, 0.01, 0.01 }, CLOCK_INTERVAL_MS = 1000,
  STATUS_EFFECT_INTERVAL_MS = 1000, DIALOG_TITLE = "2048",
}
local layout = {
  calculate = function() return { dialog_w = 1, dialog_h = 1 } end,
  build_items = function()
    return {}, {
      usercontrol = 1, new_button = 2, switch_button = 3, undo_button = 4,
      pause_button = 5, status = 6
    }
  end,
}
local real_game_session = root_loader("lib/game_session")
local stubs = {
  ["far/config"] = config,
  ["far/backend"] = { create_buffer = function() return {} end, draw_to_far_buffer = function() end },
  ["far/dialog_layout"] = layout,
  ["far/dialog_view"] = { update = function() end, apply_status_colors = function() end },
  ["lib/status_effect"] = { compute = function() return {} end },
  ["lib/game_session"] = {
    new = function(options)
      local session = real_game_session.new(options)
      local move = session.move
      function session:move(direction)
        move_directions[#move_directions + 1] = direction
        return move(self, direction)
      end
      return session
    end,
  },
  ["lib/save"] = {
    load_state = function()
      return {
        board = board, score = 0, best = 0, moves_count = 0,
        status = "", palette = "classic", elapsed_seconds = 0
      }
    end,
    save_state = function() end, clear_save = function() end,
  },
}
loader = function(name) return stubs[name] or root_loader(name) end --luacheck: allow_defined

T.describe("far timer input", function()
  T.it("keeps the first arrow key pressed during animation", function()
    local chunk = assert(loadfile("far/main.lua"))
    setfenv(chunk, setmetatable({ loader = loader }, { __index = _G }))
    local main = chunk()
    main()
    T.eq(dialog_proc({}, F.DN_KEY, 0, { name = "right" }), true)

    clock = 0.500
    animation_timer.callback(animation_timer.timer)

    T.eq(dialog_proc({}, F.DN_KEY, 0, { name = "left" }), true)
    T.eq(dialog_proc({}, F.DN_KEY, 0, { name = "right" }), true)

    config.FRAMES_PER_TICK = 100
    for _ = 1, 10 do
      if #move_directions == 2 then break end
      animation_timer.callback(animation_timer.timer)
    end
    T.eq(move_directions[1], "right")
    T.eq(move_directions[2], "left")
    T.eq(#move_directions, 2)
    T.eq(animation_timer.timer.Enabled, true)
    for _ = 1, 10 do
      if not animation_timer.timer.Enabled then break end
      animation_timer.callback(animation_timer.timer)
    end
    T.eq(animation_timer.timer.Enabled, false)
  end)
end)

T.summary_and_exit()
