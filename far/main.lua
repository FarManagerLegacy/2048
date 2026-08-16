-- FAR frontend. Game state is shared with the console through game_session;
-- this file owns FAR lifecycle, timers and event dispatch only.
local F = far.Flags

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
local ai = loader("lib/ai")
local arrow_glyphs = { up = "↑", down = "↓", left = "←", right = "→" }

local function main()
  local now
  if far.FarClock then
    now = function() return far.FarClock() / 1000000 end
  else
    now = win.Clock --luacheck: read_globals win.Clock
  end

  local saved = save.load_state()
  local initial_state = saved and board_mod.compute_status(saved.board) ~= "game_over" and saved or nil
  local session = game_session.new({ state = initial_state, clock = now })
  local screen = win.GetConsoleScreenBufferInfo() --luacheck: read_globals win.GetConsoleScreenBufferInfo
  local geom = layout.fit_to_height(screen.WindowBottom - screen.WindowTop + 1, constants.GEOMETRY_UNIT)
  local far_buffer = far_backend.create_buffer()
  local items, item_ids = layout.build_items(F, geom, far_buffer)

  local hdlg
  local closed = false
  local timer
  local clock_timer
  local active_animation
  local slide_deadline
  local pending_key
  local average_render_time = constants.ANIM_FRAME_DELAY
  local auto_play = false
  local auto_play_has_moved = false
  local auto_direction
  local auto_ready_at
  local view_state = {}

  local function set_animation_timer_interval()
    if not timer or not active_animation or active_animation:is_done() then return end
    local phase = active_animation.phases[active_animation.phase_idx]
    if active_animation.phase_idx == 1 and slide_deadline then
      local remaining = phase.total_steps - phase.step
      local delay = animation_fsm.next_frame_delay(slide_deadline, now(), remaining)
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
      local started = now()
      hdlg:ShowItem(item_ids.usercontrol, 1)
      local elapsed = now() - started
      average_render_time = 0.8 * average_render_time + 0.2 * elapsed
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
    view_state = view.update(hdlg, item_ids, geom, session, auto_play, view_state) or view_state
  end

  local function save_current()
    return save.save_state(session:snapshot())
  end

  local schedule_auto_move

  local function begin_move(direction)
    if active_animation then return end
    local result = session:move(direction)
    if not result.changed then return false end
    sync_clock_timer_interval()
    if constants.SKIP_ANIMATIONS then
      session:settle_score()
      save_current()
      update_view()
      request_board_redraw()
      if auto_play then schedule_auto_move() end
      return true
    end
    active_animation = animation_fsm.new_move_animation(
      result.new_board, result.moves, result.spawned_board, result.spawned,
      session.palette, average_render_time
    )
    slide_deadline = now() + animation_fsm.max_distance(result.moves)
      * constants.SLIDE_DURATION_PER_CELL
    update_view()
    set_animation_timer_interval()
    if timer then timer.Enabled = true end
    return true
  end

  local function set_auto_play(enabled)
    if auto_play == enabled then return end
    auto_play = enabled
    auto_direction, auto_ready_at = nil, nil
    if enabled then auto_play_has_moved = false end
    update_view()
  end

  local function start_ai_move()
    if active_animation or session.paused then return false end
    if session.status == "game_over" then
      set_auto_play(false)
      return false
    end
    local direction = auto_direction
    if direction then
      auto_direction, auto_ready_at = nil, nil
    else
      local started = now()
      direction = ai.find_best_move(session.board, "AI_AUTOPLAY")
      if not direction then
        set_auto_play(false)
        return false
      end
      local ready_at = started + constants.AUTO_PLAY_MIN_MOVE_DELAY
      if auto_play_has_moved and now() < ready_at then
        auto_direction, auto_ready_at = direction, ready_at
        if clock_timer then
          clock_timer.Interval = math.max(1, math.floor((ready_at - now()) * 1000 + 0.5))
        end
        return true
      end
    end
    local moved = begin_move(direction)
    if moved then auto_play_has_moved = true end
    return moved
  end

  local function best_move()
    local direction = ai.find_best_move(session.board, "AI_BEST_MOVE")
    return direction and begin_move(direction) or false
  end

  schedule_auto_move = function()
    far.AdvControl(F.ACTL_SYNCHRO, function()
      if not closed and auto_play then start_ai_move() end
    end)
  end

  local function start_pending_move()
    local key = pending_key
    pending_key = nil
    if session.status ~= "game_over" and not session.paused then begin_move(key) end
  end

  local function on_timer(handle)
    handle.Enabled = false
    if closed then return end
    if active_animation and not active_animation:is_done() then
      active_animation:advance(config.FRAMES_PER_TICK)
      request_board_redraw()
      if active_animation.phase_idx ~= 1 then slide_deadline = nil end
      if active_animation:is_done() then
        handle.Enabled = false
        session:settle_score()
        active_animation = nil
        sync_clock_timer_interval()
        save_current()
        update_view()
        if auto_play and session.status == "game_over" then
          pending_key = nil
          set_auto_play(false)
        elseif auto_play then
          schedule_auto_move()
        elseif pending_key then
          start_pending_move()
        end
      else
        set_animation_timer_interval()
        handle.Enabled = true
      end
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

  local function cycle_palette(step)
    if active_animation then return end
    session:cycle_palette(step)
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

  local button_actions = {
    [item_ids.new_button] = reset_to_new_game,
    [item_ids.undo_button] = undo_last_move,
    [item_ids.pause_button] = toggle_pause,
  }
  button_actions[item_ids.palette_prev_button] = function() cycle_palette(-1) end
  button_actions[item_ids.palette_next_button] = cycle_palette
  if item_ids.best_button then button_actions[item_ids.best_button] = best_move end

  local function draw_key_marker(key)
    local dialog_rect = hdlg:GetDlgRect()
    local moves_rect = hdlg:GetItemPosition(item_ids.moves)
    local color = far.AdvControl(F.ACTL_GETCOLOR, far.Colors.COL_DIALOGHIGHLIGHTTEXT)
    local arrow = arrow_glyphs[key]
    if dialog_rect and moves_rect and color and arrow then
      far.Text(dialog_rect.Left + moves_rect.Left - 1,
        dialog_rect.Top + moves_rect.Top, color, arrow)
      far.Text()
    end
  end

  local function dispatch_key(key, item_id)
    local is_arrow = arrow_glyphs[key] ~= nil
    if config.DEBUG and is_arrow then
      draw_key_marker(key)
    end
    if active_animation then
      if is_arrow then
        if not pending_key then pending_key = key end
        return true
      end
      return false
    end
    if is_arrow then
      if session.status ~= "game_over" then
        if session.paused then toggle_pause() end
        begin_move(key)
      end
      return true
    elseif key == "undo" and session:can_undo() then
      if session.paused then toggle_pause() end
      undo_last_move()
      return true
    elseif key == "pause" and item_id == item_ids.usercontrol
        and session.status ~= "game_over" then
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
      bs = "undo",
    })[name]
  end

  local function dlg_proc(dialog, msg, param1, param2)
    if msg == F.DN_INITDIALOG then
      hdlg = dialog
      timer = far.Timer(config.TIMER_INTERVAL_MS, on_timer)
      timer.Enabled = false
      clock_timer = far.Timer(config.CLOCK_INTERVAL_MS, function()
        if not closed then
          if auto_play and auto_direction and auto_ready_at then
            if now() >= auto_ready_at then
              auto_ready_at = nil
              schedule_auto_move()
            else
              clock_timer.Interval = math.max(1, math.floor((auto_ready_at - now()) * 1000 + 0.5))
            end
          elseif session.status == "won" or session.status == "game_over" then
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
      local effect = status_effect.compute(visual_status, session.paused, session.palette,
        now(), session:victory_effect())
      far_backend.draw_to_far_buffer(far_buffer, {
        tiles = current_tiles(), board_tint = effect.board_tint, fade = effect.fade,
        tile_effect = effect.tile_effect,
        palette = session.palette,
      })
      return true
    end

    if msg == F.DN_BTNCLICK then
      local prev_auto_play = auto_play
      set_auto_play(false)
      if active_animation then return true end
      local action = button_actions[param1]
      if session.paused and param1 ~= item_ids.pause_button then toggle_pause() end
      if param1 == item_ids.auto_button then
        if not prev_auto_play then
          set_auto_play(true)
          start_ai_move()
        end
      else
        action()
      end
      return true
    end

    if msg == F.DN_CTLCOLORDLGITEM and param1 == item_ids.status then
      return view.apply_status_colors(
        session:has_pending_score() and "" or session.status, param2)
    end

    if msg == F.DN_CTLCOLORDLGITEM and param1 == item_ids.time then
      local disabled = far.AdvControl(F.ACTL_GETCOLOR, far.Colors.COL_DIALOGDISABLED)
      return view.apply_disabled_colors(param2, disabled)
    end

    if msg == F.DN_CTLCOLORDLGITEM and (
      param1 == item_ids.score or param1 == item_ids.score_label
      or param1 == item_ids.best or param1 == item_ids.best_label
    ) then
      local disabled = far.AdvControl(F.ACTL_GETCOLOR, far.Colors.COL_DIALOGDISABLED)
      return view.apply_footer_colors(
        param1 == item_ids.best and session.score + session.pending_score > session.best,
        param2, disabled)
    end

    if msg == (F.DN_CONTROLINPUT or F.DN_KEY) then
      if F.DN_CONTROLINPUT and param2.EventType == F.FOCUS_EVENT then
        if param2.SetFocus == false and not auto_play then
          session:set_paused(true)
          save_current()
          update_view()
        end
        return nil
      end
      if F.DN_CONTROLINPUT and param2.EventType ~= F.KEY_EVENT then return nil end

      if auto_play then
        set_auto_play(false)
        return true
      end
      local key = (far.KeyToName or far.InputRecordToName)(param2) --luacheck: read_globals far.KeyToName
      return dispatch_key(normalize_key(key), param1) or nil
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
      auto_play = false
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
