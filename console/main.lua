-- Console entry point. The game rules and mutable state live in lib/.
local isMain = not loader
loader = loader or dofile("loader.lua")() --luacheck: globals loader

local game_session = loader("lib/game_session")
local board_mod = loader("lib/board")
local render = loader("console/render")
local tiles_mod = loader("lib/tiles")
local geometry = loader("lib/geometry")
local animation = loader("console/animation")
local screens = loader("console/screens")
local save = loader("lib/save")
local platform = loader("console/platform")
local config = loader("console/config")
local constants = loader("lib/constants")
local status_effect = loader("lib/status_effect")
local ai = loader("lib/ai")

math.randomseed(os.time())

local function main()
  local prepared, prepare_err = pcall(platform.prepare_console)
  if not prepared then
    local _, restore_err = platform.restore_console()
    if restore_err then prepare_err = prepare_err .. "\n" .. restore_err end
    error(prepare_err, 0)
  end

  local alternate = false
  local ok, err = xpcall(function()
    platform.enter_alternate_screen()
    alternate = true

    local saved, load_err = save.load_state()
    local session
    if load_err then
      if screens.corrupt_save_screen(load_err) ~= "restart" then return end
      save.clear_save()
    elseif saved and board_mod.compute_status(saved.board) ~= "game_over" then
      session = game_session.new({ state = saved, clock = platform.now })
    elseif saved then
      save.clear_save()
    end
    session = session or game_session.new({ clock = platform.now })
    geometry.set_board_dimensions(session.board_width, session.board_height)

    local function save_current()
      return save.save_state(session:snapshot())
    end

    local function do_render()
      local visual_status = session:has_pending_score() and "" or session.status
      local effect = status_effect.compute(visual_status, session.paused, session.palette,
        platform.now(), session:victory_effect())
      render.render_frame({
        tiles = tiles_mod.board_to_tiles(session.board),
        score = session.score,
        score_delta = session.pending_score,
        best = session.best,
        moves_count = session.moves_count,
        elapsed_seconds = session:current_elapsed(),
        status_text = visual_status,
        palette = session.palette,
        paused = session.paused,
        board_tint = effect.board_tint,
        fade = effect.fade,
        blink = effect.blink,
        tile_effect = effect.tile_effect,
      })
    end

    io.write("\x1b[2J\x1b[H\x1b[?25l")
    io.flush()
    do_render()
    local last_shown_second = math.floor(session:current_elapsed())
    local last_effect_render = platform.now()
    local auto_play = false
    local auto_play_has_moved = false
    local auto_direction
    local auto_ready_at

    local function execute_move(direction, preserve_input)
      if not direction then return false end
      if not preserve_input then platform.flush_input() end
      local result = session:move(direction)
      if not result.changed then return false end
      if not constants.SKIP_ANIMATIONS then
        animation.play_move(
          result.new_board, result.moves, result.spawned_board, result.spawned,
          {
            score = session.score,
            best = session.best,
            moves_count = session.moves_count,
            elapsed_seconds = session:current_elapsed(),
            score_delta = session.pending_score,
          }, session.palette
        )
      end
      if session:has_pending_score() then session:settle_score() end
      save_current()
      do_render()
      last_shown_second = math.floor(session:current_elapsed())
      return true
    end

    while true do
      if session.status == "game_over" then
        auto_play = false
        session:freeze_time()
        local outcome = screens.game_over_screen(
          session.board, session.score, session.best, session.moves_count,
          session:current_elapsed(), session:can_undo(), session.palette
        )
        if outcome == "quit" then
          save_current()
          return
        elseif outcome == "undo" and session:undo() then
          do_render()
          goto continue
        end
        session:restart()
        save.clear_save()
        save_current()
        do_render()
        goto continue
      end

      local key
      if auto_play and platform.kbhit() then
        auto_play = false
        auto_direction = nil
        platform.read_key()
        platform.flush_input()
        goto continue
      elseif auto_play then
        if not auto_direction then
          local started = platform.now()
          auto_direction = ai.find_best_move(session.board, "AI_AUTOPLAY")
          if not auto_direction then
            auto_play = false
          elseif auto_play_has_moved then
            auto_ready_at = started + constants.AUTO_PLAY_MIN_MOVE_DELAY
          else
            auto_ready_at = started
          end
        end
        if auto_play and platform.now() >= auto_ready_at then
          local direction = auto_direction
          auto_direction = nil
          if execute_move(direction, true) then
            auto_play_has_moved = true
          else
            auto_play = false
          end
        elseif auto_play then
          platform.sleep(math.min(config.IDLE_POLL_DELAY, auto_ready_at - platform.now()))
        end
        goto continue
      elseif platform.kbhit() then
        key = platform.read_key()
      else
        platform.sleep(config.IDLE_POLL_DELAY)
      end

      if key == nil then
        local current_time = platform.now()
        local sec = math.floor(session:current_elapsed())
        local effect_active = session:victory_effect() ~= nil
          or session.status == "game_over"
        if effect_active and current_time - last_effect_render
            >= constants.STATUS_EFFECT_INTERVAL_SECONDS then
          last_effect_render = current_time
          do_render()
        elseif sec ~= last_shown_second then
          last_shown_second = sec
          do_render()
        end
        goto continue
      end

      if key == "quit" then
        session:freeze_time()
        save_current()
        return
      elseif key == "restart" then
        auto_play = false
        session:restart()
        save.clear_save()
        save_current()
        do_render()
      elseif key == "pause" then
        auto_play = false
        session:set_paused(true)
        local outcome = screens.pause_screen(
          session.board, session.score, session.best, session.moves_count,
          session:current_elapsed(), session.palette
        )
        if outcome == "quit" then
          save_current()
          return
        end
        session:set_paused(false)
        do_render()
      elseif key == "palette_prev" or key == "palette_next" then
        auto_play = false
        session:cycle_palette(key == "palette_prev" and -1 or 1)
        save_current()
        do_render()
      elseif key == "undo" then
        auto_play = false
        if session:undo() then
          save_current()
          do_render()
        end
      elseif key == "up" or key == "down" or key == "left" or key == "right" then
        auto_play = false
        execute_move(key)
      elseif key == "best_move" then
        auto_play = false
        execute_move(ai.find_best_move(session.board, "AI_BEST_MOVE"))
      elseif key == "auto_play" then
        auto_play = not auto_play
        if auto_play then
          auto_play_has_moved = false
          auto_direction = nil
        end
      end

      if key ~= nil and not (auto_play and key == "auto_play")
          and not (key == "up" or key == "down"
          or key == "left" or key == "right") then
        platform.flush_input()
      end
      ::continue::
    end
  end, debug.traceback)

  local restored, restore_err = platform.restore_console()
  io.write("\x1b[?25h" .. render.OUTER_RESET)
  if alternate then platform.leave_alternate_screen() end
  io.write("\n")
  io.flush()
  if not ok then
    if restore_err then err = err .. "\nTerminal restore failed: " .. restore_err end
    error(err, 0)
  end
  if not restored then error(restore_err, 0) end
end

if isMain then
  return main()
end

return main
