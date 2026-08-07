-- Console entry point. The game rules and mutable state live in
-- lib/game_session.lua; this file owns only the Windows loop and rendering.
local ffi = require("ffi")
if ffi.os ~= "Windows" then
  io.stderr:write("This build targets Windows consoles (uses msvcrt for input).\n")
  os.exit(1)
end

local isMain = not loader
loader = loader or dofile("loader.lua")() --luacheck: globals loader

local game_session = loader("lib/game_session")
local board_mod = loader("lib/board")
local render = loader("console/render")
local tiles_mod = loader("lib/tiles")
local animation = loader("console/animation")
local screens = loader("console/screens")
local save = loader("lib/save")
local winapi = loader("console/winapi")
local config = loader("console/config")

math.randomseed(os.time())

local function notify_finished_save(status)
  local label = (status == "won") and "reached 2048 and was won" or "ended in Game Over"
  io.write("\x1b[2J\x1b[H")
  io.write(string.format(
    "\x1b[1mThe saved game already %s.\x1b[0m\n" ..
    "Starting a new game. Press any key to continue...\n", label))
  io.flush()
  winapi._getch_byte()
end

local function main()
  winapi.enable_windows_ansi()
  winapi.enter_alternate_screen()

  local saved = save.load_state()
  local session
  if saved and board_mod.compute_status(saved.board) == "" then
    session = game_session.new({ state = saved, clock = winapi.now })
  elseif saved then
    notify_finished_save(board_mod.compute_status(saved.board))
    save.clear_save()
  end
  session = session or game_session.new({ clock = winapi.now })

  local function save_current()
    return save.save_state(session:snapshot())
  end

  local function do_render()
    render.render_frame({
      tiles = tiles_mod.board_to_tiles(session.board),
      score = session.score,
      best = session.best,
      moves_count = session.moves_count,
      elapsed_seconds = session:current_elapsed(),
      status_text = session.status,
      palette = session.palette,
      paused = session.paused,
    })
  end

  io.write("\x1b[2J\x1b[H\x1b[?25l")
  io.flush()

  local ok, err = pcall(function()
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
      if winapi.kbhit() then
        key = winapi.read_key()
      else
        winapi.sleep(config.IDLE_POLL_DELAY)
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
          winapi.flush_input()
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
        winapi.flush_input()
      end
      ::continue::
    end
  end)

  io.write("\x1b[?25h" .. render.OUTER_RESET)
  winapi.leave_alternate_screen()
  io.write("\n")
  io.flush()
  if not ok then error(err, 0) end
end

if isMain then
  return main()
end

return main
