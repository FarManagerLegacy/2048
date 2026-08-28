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
local geometry = loader("lib/geometry")
local view = loader("far/dialog_view")
local status_effect = loader("lib/status_effect")
local ai = loader("lib/ai")
local util = loader("lib/util")
local platform = loader("far/platform")
util.now = platform.now

local arrow_glyphs = { up = "↑", down = "↓", left = "←", right = "→" }

local uuid = win.Uuid("C2087654-1C22-4E79-95C3-5B420CEEB481")
local function main()
  local saved, load_err = save.load_state()
  if load_err then
    local choice = far.Message("Save load error:\n" .. load_err
      .. "\nStart a new game?", config.DIALOG_TITLE, ";Ok;Cancel","w")
    if choice ~= 1 then return end
    save.clear_save()
    saved = nil
  end
  local initial_state = saved and board_mod.compute_status(saved.board) ~= "game_over" and saved or nil
  local session = game_session.new({ state = initial_state })
  geometry.set_board_dimensions(session.board_width, session.board_height)
  local screen = win.GetConsoleScreenBufferInfo()
  local geom = layout.fit_to_height(screen.WindowBottom - screen.WindowTop + 1, constants.GEOMETRY_UNIT)
  local far_buffer = far_backend.create_buffer()
  local items, item_ids = layout.build_items(F, geom, far_buffer)

  local hDlg
  local timer
  local clock_timer
  local active_animation
  local slide_deadline
  local animation_phase_started_at
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
      local delay = animation_fsm.next_frame_delay(slide_deadline, remaining)
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
    if hDlg then
      local started = platform.now()
      hDlg:ShowItem(item_ids.usercontrol, 1)
      local elapsed = platform.now() - started
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
    view_state = view.update(hDlg, item_ids, geom, session, auto_play, view_state) or view_state
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
    slide_deadline = platform.now() + animation_fsm.max_distance(result.moves)
      * constants.SLIDE_DURATION_PER_CELL
    animation_phase_started_at = slide_deadline
      - animation_fsm.slide_duration(result.moves)
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
      local started = platform.now()
      direction = ai.find_best_move(session.board, "AI_AUTOPLAY")
      if not direction then
        set_auto_play(false)
        return false
      end
      local ready_at = started + constants.AUTO_PLAY_MIN_MOVE_DELAY
      if auto_play_has_moved and platform.now() < ready_at then
        auto_direction, auto_ready_at = direction, ready_at
        if clock_timer then
          clock_timer.Interval = math.max(1, math.floor((ready_at - platform.now()) * 1000 + 0.5))
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
      if hDlg and auto_play then start_ai_move() end
    end)
  end

  local function start_pending_move()
    local key = pending_key
    pending_key = nil
    if session.status ~= "game_over" and not session.paused then begin_move(key) end
  end

  local function on_timer(handle)
    handle.Enabled = false
    if not hDlg then return end
    if active_animation and not active_animation:is_done() then
      local current_time = platform.now()
      while active_animation and not active_animation:is_done() do
        local phase = active_animation.phases[active_animation.phase_idx]
        if phase:is_done() then
          active_animation:advance(0)
          if active_animation:is_done() then break end
          local delay = config.PHASE_DELAYS[active_animation.phase_idx]
            or constants.ANIM_FRAME_DELAY
          animation_phase_started_at = animation_phase_started_at
            + phase.total_steps * delay
        else
          local delay
          if active_animation.phase_idx == 1 then
            delay = animation_fsm.slide_duration(active_animation.phases[1].moves)
              / math.max(1, phase.total_steps)
          else
            delay = config.PHASE_DELAYS[active_animation.phase_idx]
              or constants.ANIM_FRAME_DELAY
          end
          local target_step = math.floor((current_time - animation_phase_started_at) / delay)
          local frames = math.max(config.FRAMES_PER_TICK, target_step - phase.step)
          active_animation:advance(math.max(1, frames))
          if not phase:is_done() then break end
        end
      end
      request_board_redraw()
      if active_animation and active_animation.phase_idx ~= 1 then
        slide_deadline = nil
      end
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
    local dialog_rect = hDlg:GetDlgRect()
    local moves_rect = hDlg:GetItemPosition(item_ids.moves)
    local color = far.AdvControl(F.ACTL_GETCOLOR, far.Colors.COL_DIALOGHIGHLIGHTTEXT)
    local arrow = arrow_glyphs[key]
    if dialog_rect and moves_rect and color and arrow then
      far.Text(dialog_rect.Left + moves_rect.Left - 1,
        dialog_rect.Top + moves_rect.Top, color, arrow)
      far.Text()
    end
  end

  local function dispatch_key(key, item_id)
    if not key then return nil end
    local is_arrow = arrow_glyphs[key] ~= nil
    if config.DEBUG and is_arrow then
      draw_key_marker(key)
    end
    if active_animation then
      if is_arrow then
        if not pending_key then pending_key = key end
        return true
      end
      return nil
    end
    local was_paused = session.paused
    if was_paused then toggle_pause() end
    if key == "undo" and session:can_undo() then
      undo_last_move()
    elseif key == "palette_prev" then
      hDlg:SetFocus(item_ids.palette_prev_button)
      return hDlg:send(F.DN_BTNCLICK, item_ids.palette_prev_button)
    elseif session.status == "game_over" then --luacheck: ignore 542
      --nop
    elseif is_arrow then
      begin_move(key)
    elseif key=="pause" or (key=="space" and item_id == item_ids.usercontrol) then
      if not was_paused then toggle_pause() end
    else
      return nil
    end
    return true
  end

  local function normalize_key(name)
    name = tostring(name or ""):lower()
    return ({
      left = "left", up = "up", right = "right", down = "down",
      pause = "pause", space = "space",
      shiftp = "palette_prev",
      bs = "undo",
    })[name]
  end

  local function init_dialog(dialog)
    hDlg = dialog
    timer = far.Timer(config.TIMER_INTERVAL_MS, on_timer)
    timer.Enabled = false
    clock_timer = far.Timer(config.CLOCK_INTERVAL_MS, function()
      if hDlg then
        if auto_play and auto_direction and auto_ready_at then
          if platform.now() >= auto_ready_at then
            auto_ready_at = nil
            schedule_auto_move()
          else
            clock_timer.Interval = math.max(1, math.floor((auto_ready_at - platform.now()) * 1000 + 0.5))
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
  end

  local function draw_usercontrol()
      local visual_status = session:has_pending_score() and "" or session.status
      local effect = status_effect.compute(visual_status, session.paused, session.palette,
         platform.now(), session:victory_effect())
      far_backend.draw_to_far_buffer(far_buffer, {
        tiles = current_tiles(), board_tint = effect.board_tint, fade = effect.fade,
        tile_effect = effect.tile_effect,
        palette = session.palette,
      })
  end

  local function handle_button(item_id)
    local prev_auto_play = auto_play
    set_auto_play(false)
    if active_animation then return true end
    local action = button_actions[item_id]
    if session.paused and item_id ~= item_ids.pause_button then toggle_pause() end
    if item_id == item_ids.auto_button then
      if not prev_auto_play then
        set_auto_play(true)
        start_ai_move()
      end
    else
      action()
    end
    return true
  end

  local function handle_colors(item_id, param2)
    if item_id == item_ids.status then
      return view.apply_status_colors(
        session:has_pending_score() and "" or session.status, param2)
    end

    if item_id == item_ids.time then
      local disabled = far.AdvControl(F.ACTL_GETCOLOR, far.Colors.COL_DIALOGDISABLED)
      return view.apply_disabled_colors(param2, disabled)
    end

    if item_id == item_ids.score or item_id == item_ids.score_label
        or item_id == item_ids.best or item_id == item_ids.best_label then
      local disabled = far.AdvControl(F.ACTL_GETCOLOR, far.Colors.COL_DIALOGDISABLED)
      return view.apply_footer_colors(
        item_id == item_ids.best and session.score + session.pending_score > session.best,
        param2, disabled)
    end
    return nil
  end

  local function handle_key_input(item_id, record)
      if F.DN_CONTROLINPUT and record.EventType == F.FOCUS_EVENT then
        if record.SetFocus == false and not auto_play then
          if not session.paused then
            session:set_paused("lostfocus")
            save_current()
            update_view()
          end
          hDlg:SetFocus(item_ids.usercontrol)
        elseif record.SetFocus == true and session.paused == "lostfocus" then
          session:set_paused(false)
          save_current()
          update_view()
        end
        return nil
      end
      if F.DN_CONTROLINPUT and record.EventType ~= F.KEY_EVENT then return nil end

      if auto_play then
        set_auto_play(false)
        return true
      end
      local key
      --luacheck: read_globals far.KeyToName
      if far.KeyToName then
        key = far.KeyToName(record)
      else
        key = far.InputRecordToName(record)
        if 0~=bit64.band(F.SHIFT_PRESSED, record.ControlKeyState) and not key:match("Shift") then
          key = "Shift"..key
        end
      end

      return dispatch_key(normalize_key(key), item_id)
  end

  local function dlg_proc(dialog, msg, param1, param2)
    if msg == F.DN_INITDIALOG then init_dialog(dialog); return true end
    if msg == F.DN_DRAWDLGITEM and param1 == item_ids.usercontrol then
      draw_usercontrol()
      return true
    end
    if msg == F.DN_BTNCLICK then return handle_button(param1) end
    if msg == F.DN_CTLCOLORDLGITEM then return handle_colors(param1, param2) end
    if msg == (F.DN_CONTROLINPUT or F.DN_KEY) then
      return handle_key_input(param1, param2)
    end
    return nil
  end

  far.Dialog(uuid, -1, -1, geom.dialog_w, geom.dialog_h,
    config.DIALOG_TITLE, items, 0, dlg_proc)
  hDlg = nil
  session:settle_score()
  save_current()
  close_timers()
end

if isMain then
  return main()
end

return main
