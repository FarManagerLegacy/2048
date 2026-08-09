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
local status_effect = loader("lib/status_effect")

local function main()
  local function now()
    return far.FarClock() / 1000000
  end

  local saved = save.load_state()
  local initial_state = saved and board_mod.compute_status(saved.board) == "" and saved or nil
  local session = game_session.new({ state = initial_state, clock = now })
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
  local settling_score = false

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

  local function request_board_redraw()
    if hdlg and not closed then
      far.SendDlgMessage(hdlg, "DM_SHOWITEM", item_ids.usercontrol, 1)
    end
  end

  local function sync_clock_timer_interval()
    if clock_timer then
      clock_timer.Interval = session.status ~= ""
        and config.STATUS_EFFECT_INTERVAL_MS
        or config.CLOCK_INTERVAL_MS
    end
  end

  local function update_view()
    view.update(far, hdlg, item_ids, geom, session, request_redraw)
  end

  local function save_current()
    return save.save_state(session:snapshot())
  end

  local function settle_score_now()
    if not session:has_pending_score() then return end
    session:settle_score()
    settling_score = false
    active_animation = nil
    if timer then timer.Enabled = false end
    sync_clock_timer_interval()
    save_current()
    update_view()
  end

  local function begin_move(direction)
    if session:has_pending_score() then settle_score_now() end
    if active_animation and not active_animation:is_done() then return end
    local result = session:move(direction)
    if not result.changed then return end
    sync_clock_timer_interval()
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
        if session:has_pending_score() then
          settling_score = true
          handle.Interval = 1000
          update_view()
        else
          handle.Enabled = false
          save_current()
        end
      else
        set_animation_timer_interval()
      end
    elseif settling_score then
      session:settle_score()
      settling_score = false
      active_animation = nil
      handle.Enabled = false
      sync_clock_timer_interval()
      save_current()
      update_view()
    else
      handle.Enabled = false
    end
  end

  local function reset_to_new_game()
    settle_score_now()
    session:restart()
    sync_clock_timer_interval()
    active_animation = nil
    if timer then timer.Enabled = false end
    save.clear_save()
    save_current()
    update_view()
  end

  local function undo_last_move()
    settle_score_now()
    if not session:undo() then return end
    sync_clock_timer_interval()
    active_animation = nil
    if timer then timer.Enabled = false end
    save_current()
    update_view()
  end

  local function cycle_palette()
    settle_score_now()
    session:cycle_palette()
    save_current()
    update_view()
  end

  local function toggle_pause()
    settle_score_now()
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

  local function dispatch_key(key)
    if key == "up" or key == "down" or key == "left" or key == "right" then
      if session.status == "" and not session.paused then begin_move(key) return true end
    elseif key == "pause" and current_focus == item_ids.usercontrol and session.status == "" then
      toggle_pause()
      return true
    end
    return false
  end

  local function normalize_key(name)
    name = tostring(name or ""):lower()
    return ({
      left = "left", up = "up", right = "right", down = "down",
      space = "pause",
    })[name]
  end

  local function dlg_proc(dialog, msg, param1, param2)
    if msg == F.DN_INITDIALOG then
      hdlg = dialog
      timer = far.Timer(config.TIMER_INTERVAL_MS, on_timer)
      timer.Enabled = false
      clock_timer = far.Timer(config.CLOCK_INTERVAL_MS, function()
        if not closed then
          if session.status == "won" or session.status == "game_over" then
            request_board_redraw()
          else
            update_view()
          end
        end
      end)
      clock_timer.Enabled = true
      update_view()
      return true
    end

    if msg == F.DN_DRAWDLGITEM and param1 == item_ids.usercontrol then
      local effect = status_effect.compute(session.status, session.paused, session.palette, now())
      far_backend.draw_to_far_buffer(far_buffer, {
        tiles = current_tiles(), board_tint = effect.board_tint, fade = effect.fade,
        palette = session.palette,
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
      return view.apply_status_colors(F, bor,
        session:has_pending_score() and "" or session.status, param2)
    end

    if not F.DN_KEY and msg == F.DN_CONTROLINPUT and param2.KeyDown ~= false then
      return dispatch_key(normalize_key(far.InputRecordToName(param2))) or nil
    end

    if F.DN_KEY and msg == F.DN_KEY then
      return dispatch_key(normalize_key(far.KeyToName(param2))) or nil
    end

    if msg == F.DN_CLOSE then
      settle_score_now()
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
