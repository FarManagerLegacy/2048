-- Console entry point. The game rules and mutable state live in lib/.
local isMain = not loader
loader = loader or dofile("loader.lua")() --luacheck: globals loader

local game_session = loader("lib/game_session")
local board_mod = loader("lib/board")
local render = loader("console/render")
local tiles_mod = loader("lib/tiles")
local animation = loader("console/animation")
local screens = loader("console/screens")
local save = loader("lib/save")
local platform = loader("console/platform")
local config = loader("console/config")
local status_effect = loader("lib/status_effect")

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

    local saved = save.load_state()
    local session
    if saved and board_mod.compute_status(saved.board) == "" then
      session = game_session.new({ state = saved, clock = platform.now })
    elseif saved then
      save.clear_save()
    end
    session = session or game_session.new({ clock = platform.now })

    local function save_current()
      return save.save_state(session:snapshot())
    end

    local function do_render()
      local effect = status_effect.compute(session.status, session.paused, session.palette,
        session:current_elapsed())
      render.render_frame({
        tiles = tiles_mod.board_to_tiles(session.board),
        score = session.score,
        best = session.best,
        moves_count = session.moves_count,
        elapsed_seconds = session:current_elapsed(),
        status_text = session.status,
        palette = session.palette,
        paused = session.paused,
        board_tint = effect.board_tint,
        fade = effect.fade,
        blink = effect.blink,
      })
    end

    io.write("\x1b[2J\x1b[H\x1b[?25l")
    io.flush()
    do_render()
    local last_shown_second = math.floor(session:current_elapsed())

    while true do
      if session.status == "game_over" or session.status == "won" then
        session:freeze_time()
        local screen = session.status == "won" and screens.win_screen or screens.game_over_screen
        local outcome = screen(
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
      if platform.kbhit() then
        key = platform.read_key()
      else
        platform.sleep(config.IDLE_POLL_DELAY)
      end

      if key == nil then
        local sec = math.floor(session:current_elapsed())
        if sec ~= last_shown_second then
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
        session:restart()
        save.clear_save()
        save_current()
        do_render()
      elseif key == "pause" then
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
      elseif key == "palette" then
        session:cycle_palette()
        save_current()
        do_render()
      elseif key == "undo" then
        if session:undo() then
          save_current()
          do_render()
        end
      elseif key == "up" or key == "down" or key == "left" or key == "right" then
        local result = session:move(key)
        if result.changed then
          -- Discard keys queued before this move. Keys pressed while the
          -- blocking animation is running are intentionally kept for the
          -- next loop iteration.
          platform.flush_input()
          animation.play_move(
            result.new_board, result.moves, result.spawned_board, result.spawned,
            {
              score = session.score,
              best = session.best,
              moves_count = session.moves_count,
              elapsed_seconds = session:current_elapsed(),
            }, session.palette
          )
          save_current()
          do_render()
          last_shown_second = math.floor(session:current_elapsed())
        end
      end

      if key ~= nil and not (key == "up" or key == "down"
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
