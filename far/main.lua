-- FAR frontend. Game state is shared with the console through game_session;
-- this file owns FAR lifecycle, timers and event dispatch only.
local F = far.Flags
local bor = bit64.bor

local isMain = not loader
loader = loader or dofile("loader.lua")() --luacheck: globals loader

local board_mod = loader("lib/board")
local game_session = loader("lib/game_session")
local constants = loader("lib/constants")
local config = loader("far/config")
local far_backend = loader("far/backend")
local animation_fsm = loader("lib/animation_fsm")
local tiles_mod = loader("lib/tiles")
local save = loader("lib/save")
local layout = loader("far/dialog_layout")
local view = loader("far/dialog_view")
local DIRECTION_KEYS = { Left = "left", Up = "up", Right = "right", Down = "down" }

local function main()
  local saved = save.load_state()
  local initial_state = saved and board_mod.compute_status(saved.board) == "" and saved or nil
  local session = game_session.new({ state = initial_state, clock = os.clock })
  local geom = layout.calculate()
  local far_buffer = far_backend.create_buffer()
  local items, item_ids = layout.build_items(F, geom, far_buffer)

  local hdlg
  local closed = false
  local timer
  local clock_timer
  local active_animation
  local current_focus
  local previous_focus

  local function set_animation_timer_interval()
    if not timer or not active_animation or active_animation:is_done() then return end
    local delay = config.PHASE_DELAYS[active_animation.phase_idx]
      or constants.ANIM_FRAME_DELAY
    timer.Interval = math.floor(delay * 1000 + 0.5)
  end

  local function current_tiles()
    if active_animation and not active_animation:is_done() then
      return active_animation:tiles()
    end
    return tiles_mod.board_to_tiles(session.board)
  end

  local function request_redraw()
    if hdlg and not closed then
      far.SendDlgMessage(hdlg, "DM_REDRAW", 0, nil)
    end
  end

  local function update_view()
    view.update(far, hdlg, item_ids, geom, session, request_redraw)
  end

  local function save_current()
    return save.save_state(session:snapshot())
  end

  local function begin_move(direction)
    if active_animation and not active_animation:is_done() then return end
    local result = session:move(direction)
    if not result.changed then return end
    active_animation = animation_fsm.new_move_animation(
      result.new_board, result.moves, result.spawned_board, result.spawned,
      session.palette
    )
    set_animation_timer_interval()
    if timer then timer.Enabled = true end
    update_view()
  end

  local function on_timer(handle)
    if closed or session.paused then
      handle.Enabled = false
      return
    end
    if active_animation and not active_animation:is_done() then
      active_animation:advance(config.FRAMES_PER_TICK)
      request_redraw()
      if active_animation:is_done() then
        handle.Enabled = false
        save_current()
      else
        set_animation_timer_interval()
      end
    else
      handle.Enabled = false
    end
  end

  local function reset_to_new_game()
    session:restart()
    active_animation = nil
    if timer then timer.Enabled = false end
    save.clear_save()
    save_current()
    update_view()
  end

  local function undo_last_move()
    if not session:undo() then return end
    active_animation = nil
    if timer then timer.Enabled = false end
    save_current()
    update_view()
  end

  local function cycle_palette()
    session:cycle_palette()
    save_current()
    update_view()
  end

  local function toggle_pause()
    session:set_paused(not session.paused)
    if timer then
      timer.Enabled = not session.paused and active_animation ~= nil
        and not active_animation:is_done()
    end
    save_current()
    update_view()
  end

  local function close_timers()
    if timer then
      timer.Enabled = false
      timer:Close()
      timer = nil
    end
    if clock_timer then
      clock_timer.Enabled = false
      clock_timer:Close()
      clock_timer = nil
    end
  end

  local function restore_usercontrol_focus(should_restore)
    if should_restore then
      far.SendDlgMessage(hdlg, 'DM_SETFOCUS', item_ids.usercontrol, nil)
    end
  end

  local button_actions = {
    [item_ids.new_button] = reset_to_new_game,
    [item_ids.switch_button] = cycle_palette,
    [item_ids.undo_button] = undo_last_move,
    [item_ids.pause_button] = toggle_pause,
  }
  local function dlg_proc(dialog, msg, param1, param2)
    if msg == F.DN_INITDIALOG then
      hdlg = dialog
      timer = far.Timer(config.TIMER_INTERVAL_MS, on_timer)
      timer.Enabled = false
      clock_timer = far.Timer(config.CLOCK_INTERVAL_MS, function()
        if not closed then update_view() end
      end)
      clock_timer.Enabled = true
      update_view()
      return true
    end

    if msg == F.DN_DRAWDLGITEM and param1 == item_ids.usercontrol then
      local fade = session.paused and 0.55 or 0
      if session.status == "game_over" then fade = math.max(fade, 0.45) end
      far_backend.draw_to_far_buffer(far_buffer, {
        tiles = current_tiles(), fade = fade, palette = session.palette,
      })
      return true
    end

    if msg == F.DN_BTNCLICK then
      local action = button_actions[param1]
      if not action then return nil end

      local restore_focus = current_focus == item_ids.usercontrol
        or previous_focus == item_ids.usercontrol
      if session.paused and param1 ~= item_ids.pause_button then toggle_pause() end
      action()
      restore_usercontrol_focus(restore_focus)
      return true
    end

    if msg == F.DN_GOTFOCUS then
      previous_focus, current_focus = current_focus, param1
      return nil
    end

    if msg == F.DN_CTLCOLORDLGITEM and param1 == item_ids.status then
      return view.apply_status_colors(F, bor, session.status, param2)
    end

    if not F.DN_KEY and msg == F.DN_CONTROLINPUT and param2.KeyDown ~= false then
      local key = DIRECTION_KEYS[far.InputRecordToName(param2)]
      if (key == "up" or key == "down" or key == "left" or key == "right")
          and session.status == "" and not session.paused then
        begin_move(key)
        return true
      end
    end

    if F.DN_KEY and msg == F.DN_KEY then
      local key = DIRECTION_KEYS[far.KeyToName(param2)]
      if (key == "up" or key == "down" or key == "left" or key == "right")
          and session.status == "" and not session.paused then
        begin_move(key)
        return true
      end
    end

    if msg == F.DN_CLOSE then
      if closed then return true end
      closed = true
      hdlg = nil
      save_current()
      close_timers()
      return true
    end
    return nil
  end

  far.Dialog(nil, -1, -1, geom.dialog_w, geom.dialog_h,
    config.DIALOG_TITLE, items, 0, dlg_proc)
end

if isMain then
  return main()
end

return main
