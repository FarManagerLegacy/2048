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
local arrow_keys = { up = true, down = true, left = true, right = true }

local function main()
  local now
  if far.FarClock then
    now = function() return far.FarClock() / 1000000 end
  else
    now = win.Clock --luacheck: read_globals win.Clock
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
  local slide_deadline
  local slide_render_seconds = 0
  local pending_key

  local function set_animation_timer_interval()
    if not timer or not active_animation or active_animation:is_done() then return end
    local phase = active_animation.phases[active_animation.phase_idx]
    if active_animation.phase_idx == 1 and slide_deadline then
      local remaining = phase.total_steps - phase.step
      local delay = animation_fsm.next_frame_delay(slide_deadline, now(), remaining, slide_render_seconds)
      timer.Interval = math.max(1, math.floor(delay * 1000 + 0.5))
      return
    end
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

  local function request_board_redraw()
    if hdlg and not closed then
      -- FAR implements DM_SHOWITEM by sending DM_REDRAW for the dialog.
      far.SendDlgMessage(hdlg, "DM_SHOWITEM", item_ids.usercontrol, 1)
    end
  end

  local function sync_clock_timer_interval()
    if clock_timer then
      clock_timer.Interval = session.status ~= "" and not session:has_pending_score()
        and config.STATUS_EFFECT_INTERVAL_MS
        or config.CLOCK_INTERVAL_MS
    end
  end

  local function update_view()
    view.update(far, hdlg, item_ids, geom, session)
  end

  local function save_current()
    return save.save_state(session:snapshot())
  end

  local function begin_move(direction)
    if active_animation then return end
    local result = session:move(direction)
    if not result.changed then return false end
    sync_clock_timer_interval()
    active_animation = animation_fsm.new_move_animation(
      result.new_board, result.moves, result.spawned_board, result.spawned,
      session.palette
    )
    slide_deadline = now() + constants.SLIDE_DURATION_SECONDS
    update_view()
    set_animation_timer_interval()
    if timer then timer.Enabled = true end
    return true
  end

  local function start_pending_move()
    local key = pending_key
    pending_key = nil
    if key and session.status == "" and not session.paused then begin_move(key) end
  end

  local function on_timer(handle)
    if closed then
      handle.Enabled = false
      return
    end
    if active_animation and not active_animation:is_done() then
      active_animation:advance(config.FRAMES_PER_TICK)
      local render_started = now()
      request_board_redraw()
      slide_render_seconds = now() - render_started
      if active_animation.phase_idx ~= 1 then slide_deadline = nil end
      if active_animation:is_done() then
        handle.Enabled = false
        session:settle_score()
        active_animation = nil
        sync_clock_timer_interval()
        save_current()
        update_view()
        start_pending_move()
      else
        set_animation_timer_interval()
      end
    else
      handle.Enabled = false
    end
  end

  local function reset_to_new_game()
    if active_animation then return end
    pending_key = nil
    session:restart()
    sync_clock_timer_interval()
    active_animation = nil
    if timer then timer.Enabled = false end
    save.clear_save()
    save_current()
    update_view()
  end

  local function undo_last_move()
    if active_animation then return end
    pending_key = nil
    if not session:undo() then return end
    sync_clock_timer_interval()
    active_animation = nil
    if timer then timer.Enabled = false end
    save_current()
    update_view()
  end

  local function cycle_palette()
    if active_animation then return end
    session:cycle_palette()
    save_current()
    update_view()
  end

  local function toggle_pause()
    if active_animation then return end
    session:set_paused(not session.paused)
    if timer then
      timer.Enabled = active_animation ~= nil and not active_animation:is_done()
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
    local is_arrow = arrow_keys[key]
    if active_animation then
      if is_arrow then
        if not pending_key then pending_key = key end
        return true
      end
      return false
    end
    if is_arrow then
      if session.status == "" and not session.paused then
        if begin_move(key) then return true end
      end
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
      local visual_status = session:has_pending_score() and "" or session.status
      local effect = status_effect.compute(visual_status, session.paused, session.palette, now())
      far_backend.draw_to_far_buffer(far_buffer, {
        tiles = current_tiles(), board_tint = effect.board_tint, fade = effect.fade,
        palette = session.palette,
      })
      return true
    end

    if msg == F.DN_BTNCLICK then
      if active_animation then return true end
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
      return dispatch_key(normalize_key(far.KeyToName(param2))) or nil --luacheck: read_globals far.KeyToName
    end

    if msg == F.DN_CLOSE then
      if closed then return true end
      closed = true
      hdlg = nil
      pending_key = nil
      session:settle_score()
      active_animation = nil
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
