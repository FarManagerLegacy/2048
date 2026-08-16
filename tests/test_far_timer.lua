local root_loader = dofile("loader.lua")()
local T = root_loader("tests/test_runner")

local clock = 0
local animation_timer
local clock_timer
local dialog_proc
local move_directions = {}
local auto_play_states = {}
local palette_states = {}
local force_terminal
local redraw_seconds = 0
local animation_frame_intervals = {}
local synchro_callback
local focused_item
local F = {
  -- DN_KEY and far.KeyToName are far2m-only; current FAR uses DN_CONTROLINPUT.
  DN_INITDIALOG = "init", DN_CONTROLINPUT = "input",
  DN_DRAWDLGITEM = "draw", DN_BTNCLICK = "click", DN_GOTFOCUS = "focus",
  DN_CTLCOLORDLGITEM = "color", DN_CLOSE = "close",
  KEY_EVENT = "key", FOCUS_EVENT = "focus", ACTL_SYNCHRO = "synchro",
  SHIFT_PRESSED = 1,
}

far = { --luacheck: allow_defined
  Flags = F,
  FarClock = function() return clock * 1000000 end,
  Timer = function(_, callback)
    local timer = { Enabled = false, Interval = 0, Close = function() end }
    if not animation_timer then animation_timer = { timer = timer, callback = callback } end
    if animation_timer.timer ~= timer and not clock_timer then
      clock_timer = { timer = timer, callback = callback }
    end
    return timer
  end,
  Dialog = function(_, _, _, _, _, _, _, _, callback)
    local hdlg = {
      ShowItem = function()
        clock = clock + redraw_seconds
      end,
      SetFocus = function(_, item) focused_item = item end,
      send = function(_, message, item) return dialog_proc(hdlg, message, item, nil) end,
    }
    dialog_proc = callback
    callback(hdlg, F.DN_INITDIALOG, 0, nil)
  end,
  SendDlgMessage = function(_, message, item)
    if (message == "DM_SHOWITEM" or message == "DM_REDRAW") and dialog_proc then
      dialog_proc({}, F.DN_DRAWDLGITEM, item, nil)
    end
  end,
  AdvControl = function(command, callback)
    if command == F.ACTL_SYNCHRO then synchro_callback = callback end
  end,
  InputRecordToName = function(record) return record.name end,
}
win = { --luacheck: allow_defined
  Uuid = function(value) return value end,
  GetConsoleScreenBufferInfo = function()
    return { WindowTop = 0, WindowBottom = 31 }
  end,
}
bit64 = { --luacheck: allow_defined
  bor = function(a, b) return a + b end,
  band = function(a, b) return a == b and a or 0 end,
}

local board = {
  { 2, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 },
}
local config = {
  FRAMES_PER_TICK = 1, TIMER_INTERVAL_MS = 1,
  PHASE_DELAYS = { 0.01, 0.01, 0.01 }, CLOCK_INTERVAL_MS = 1000,
  STATUS_EFFECT_INTERVAL_MS = 1000, DIALOG_TITLE = "2048",
  AI_MAX_DEPTH = 4, AI_BUDGET_MS = 40,
}
local layout = {
  calculate = function() return { dialog_w = 1, dialog_h = 1 } end,
  build_items = function()
    return {}, {
      usercontrol = 1, new_button = 2, undo_button = 4,
      pause_button = 5, auto_button = 6, status = 7,
      palette_prev_button = 8, palette_next_button = 9,
    }
  end,
}
layout.fit_to_height = layout.calculate
local real_game_session = root_loader("lib/game_session")
local real_animation_fsm = root_loader("lib/animation_fsm")
local stubs = {
  ["far/config"] = config,
  ["far/backend"] = { create_buffer = function() return {} end, draw_to_far_buffer = function() end },
  ["far/dialog_layout"] = layout,
  ["far/dialog_view"] = {
    update = function(_, _, _, session, auto_play)
      auto_play_states[#auto_play_states + 1] = auto_play
      palette_states[#palette_states + 1] = session.palette
    end,
    apply_status_colors = function() end,
  },
  ["lib/status_effect"] = { compute = function() return {} end },
  ["lib/animation_fsm"] = setmetatable({
    new_move_animation = function(...)
      animation_frame_intervals[#animation_frame_intervals + 1] = select(6, ...)
      return real_animation_fsm.new_move_animation(...)
    end,
  }, { __index = real_animation_fsm }),
  ["lib/game_session"] = {
    new = function(options)
      local session = real_game_session.new(options)
      local move = session.move
      function session:move(direction)
        move_directions[#move_directions + 1] = direction
        return move(self, direction)
      end
      if force_terminal then session.status = "game_over" end
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
  T.it("delays auto moves after the first when animations are skipped", function()
    animation_timer, clock_timer, synchro_callback, move_directions = nil, nil, nil, {}
    local constants = root_loader("lib/constants")
    local old_skip, old_delay = constants.SKIP_ANIMATIONS, constants.AUTO_PLAY_MIN_MOVE_DELAY
    constants.SKIP_ANIMATIONS, constants.AUTO_PLAY_MIN_MOVE_DELAY = true, 1
    local chunk = assert(loadfile("far/main.lua"))
    setfenv(chunk, setmetatable({ loader = loader }, { __index = _G }))
    local main = chunk()
    main()

    dialog_proc({}, F.DN_BTNCLICK, 6, nil)
    synchro_callback()
    local moves = #move_directions
    constants.SKIP_ANIMATIONS, constants.AUTO_PLAY_MIN_MOVE_DELAY = old_skip, old_delay
    animation_timer, clock_timer, synchro_callback, move_directions = nil, nil, nil, {}
    T.eq(moves, 1)
  end)

  T.it("skips animations when configured", function()
    animation_timer, synchro_callback = nil, nil
    move_directions = {}
    local constants = root_loader("lib/constants")
    constants.SKIP_ANIMATIONS = true
    local chunk = assert(loadfile("far/main.lua"))
    setfenv(chunk, setmetatable({ loader = loader }, { __index = _G }))
    local main = chunk()
    main()

    dialog_proc({}, F.DN_CONTROLINPUT, 0, { EventType = F.KEY_EVENT, name = "right" })
    local enabled = animation_timer.timer.Enabled
    constants.SKIP_ANIMATIONS = nil
    animation_timer, move_directions = nil, {}
    T.eq(enabled, false)
  end)

  T.it("keeps the first arrow key pressed during animation", function()
    local chunk = assert(loadfile("far/main.lua"))
    setfenv(chunk, setmetatable({ loader = loader }, { __index = _G }))
    local main = chunk()
    main()
    T.eq(dialog_proc({}, F.DN_CONTROLINPUT, 0, { EventType = F.KEY_EVENT, KeyDown = true, name = "right" }), true)

    clock = 0.500
    animation_timer.callback(animation_timer.timer)

    T.eq(dialog_proc({}, F.DN_CONTROLINPUT, 0, { EventType = F.KEY_EVENT, KeyDown = true, name = "left" }), true)
    T.eq(dialog_proc({}, F.DN_CONTROLINPUT, 0, { EventType = F.KEY_EVENT, KeyDown = true, name = "right" }), true)

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

  T.it("keeps auto play running across focus records", function()
    animation_timer, synchro_callback = nil, nil
    local chunk = assert(loadfile("far/main.lua"))
    setfenv(chunk, setmetatable({ loader = loader }, { __index = _G }))
    local main = chunk()
    main()

    local moves_before = #move_directions
    dialog_proc({}, F.DN_BTNCLICK, 6, nil)
    T.eq(#move_directions, moves_before + 1)
    T.eq(dialog_proc({}, F.DN_CONTROLINPUT, 0, { EventType = F.FOCUS_EVENT }), nil)

    config.FRAMES_PER_TICK = 100
    for _ = 1, 2 do animation_timer.callback(animation_timer.timer) end
    T.eq(synchro_callback ~= nil, true)
  end)

  T.it("toggles pause with Pause and restores focus to the game field", function()
    animation_timer, focused_item = nil, nil
    local chunk = assert(loadfile("far/main.lua"))
    setfenv(chunk, setmetatable({ loader = loader }, { __index = _G }))
    local main = chunk()
    main()

    dialog_proc({}, F.DN_CONTROLINPUT, 0, { EventType = F.KEY_EVENT, name = "Pause" })
    T.eq(dialog_proc({}, F.DN_CONTROLINPUT, 1, { EventType = F.KEY_EVENT, name = "Pause" }), true)
    T.eq(dialog_proc({}, F.DN_CONTROLINPUT, 0, { EventType = F.FOCUS_EVENT, SetFocus = false }), nil)
    T.eq(focused_item, 1)
  end)

  T.it("uses Shift+P to click the previous palette button", function()
    animation_timer, palette_states = nil, {}
    local chunk = assert(loadfile("far/main.lua"))
    setfenv(chunk, setmetatable({ loader = loader }, { __index = _G }))
    local main = chunk()
    main()

    T.eq(dialog_proc({}, F.DN_CONTROLINPUT, 1,
      { EventType = F.KEY_EVENT, name = "p", ControlKeyState = F.SHIFT_PRESSED }), true)
    T.eq(palette_states[#palette_states], "sky")
    T.eq(focused_item, 8)
  end)

  T.it("stops auto play when the game is already over", function()
    animation_timer, synchro_callback = nil, nil
    auto_play_states, force_terminal = {}, true
    local chunk = assert(loadfile("far/main.lua"))
    setfenv(chunk, setmetatable({ loader = loader }, { __index = _G }))
    local main = chunk()
    main()

    dialog_proc({}, F.DN_BTNCLICK, 6, nil)
    T.eq(auto_play_states[#auto_play_states], false)
    force_terminal = nil
  end)

  T.it("uses full redraw time to pace the next animation", function()
    animation_timer, redraw_seconds = nil, 0.1
    animation_frame_intervals = {}
    config.FRAMES_PER_TICK = 100
    local chunk = assert(loadfile("far/main.lua"))
    setfenv(chunk, setmetatable({ loader = loader }, { __index = _G }))
    local main = chunk()
    main()

    dialog_proc({}, F.DN_CONTROLINPUT, 0, { EventType = F.KEY_EVENT, name = "right" })
    for _ = 1, 10 do
      if not animation_timer.timer.Enabled then break end
      animation_timer.callback(animation_timer.timer)
    end
    dialog_proc({}, F.DN_CONTROLINPUT, 0, { EventType = F.KEY_EVENT, name = "left" })
    T.ok(animation_frame_intervals[2] > animation_frame_intervals[1])
    redraw_seconds = 0
  end)

  T.it("consumes invalid arrow input", function()
    animation_timer, clock_timer, move_directions = nil, nil, {}
    board = {
      { 2, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 },
    }
    local chunk = assert(loadfile("far/main.lua"))
    setfenv(chunk, setmetatable({ loader = loader }, { __index = _G }))
    local main = chunk()
    main()

    T.eq(dialog_proc({}, F.DN_CONTROLINPUT, 0, { EventType = F.KEY_EVENT, name = "left" }), true)
    T.eq(#move_directions, 1)
  end)

end)

T.summary_and_exit()
