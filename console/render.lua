-- ANSI-truecolor rendering of the board to a string, built to stdout.
local geometry = loader("lib/geometry")
local color = loader("lib/color")
local util = loader("lib/util")
local canvas = loader("lib/tile_canvas")

local CELL_W, CELL_H = geometry.CELL_W, geometry.CELL_H
local GAP_X, GAP_Y = geometry.GAP_X, geometry.GAP_Y
local BOARD_W, BOARD_H = geometry.BOARD_W, geometry.BOARD_H

local M = {}
M.OUTER_RESET = "\x1b[0m"

-- U+23F8 PAUSE SYMBOL as raw UTF-8 bytes (LuaJIT has no \uXXXX escape).
local PAUSE_SYMBOL = "\xe2\x8f\xb8"

local function render_buffer(buf)
  local lines = {}
  for y = 1, BOARD_H do
    local row = buf[y]
    local parts = {}
    local run_chars = {}
    local cur_fg, cur_bg = "__unset__", "__unset__"

    local function flush_run()
      if #run_chars > 0 then
        parts[#parts + 1] = table.concat(run_chars)
        run_chars = {}
      end
    end

    for x = 1, BOARD_W do
      local ch, fg, bg = row[x][1], row[x][2], row[x][3]
      local fg_key = fg and table.concat(fg, ",") or "nil"
      local bg_key = bg and table.concat(bg, ",") or "nil"
      if fg_key ~= cur_fg or bg_key ~= cur_bg then
        flush_run()
        local code = "\x1b[0m"
        if bg then
          code = code .. string.format("\x1b[48;2;%d;%d;%dm", bg[1], bg[2], bg[3])
        end
        if fg then
          code = code .. string.format("\x1b[38;2;%d;%d;%dm", fg[1], fg[2], fg[3])
        end
        parts[#parts + 1] = code
        cur_fg, cur_bg = fg_key, bg_key
      end
      run_chars[#run_chars + 1] = ch
    end
    flush_run()
    parts[#parts + 1] = "\x1b[0m\x1b[K"
    lines[#lines + 1] = table.concat(parts)
  end
  return table.concat(lines, "\n")
end

local function center_text(text, width)
  local pad = math.max(0, width - #text)
  local left = math.floor(pad / 2)
  local right = pad - left
  return string.rep(" ", left) .. text .. string.rep(" ", right)
end

local function centered_styled_line(parts, width)
  local visible = {}
  for _, part in ipairs(parts) do
    visible[#visible + 1] = part.text
  end
  local text = table.concat(visible)
  local pad = math.max(0, width - #text)
  local left = math.floor(pad / 2)
  local right = pad - left
  local out = { string.rep(" ", left) }
  for _, part in ipairs(parts) do
    out[#out + 1] = part.style or ""
    out[#out + 1] = part.text
    out[#out + 1] = "\x1b[0m"
  end
  out[#out + 1] = string.rep(" ", right)
  out[#out + 1] = "\x1b[K"
  return table.concat(out)
end

function M.render_frame(opts)
  local tiles = opts.tiles
  local score = opts.score
  local score_delta = opts.score_delta or 0
  if score_delta > 0 then score = string.format("%d +%d", score, score_delta) end
  local best = opts.best
  local moves_count = opts.moves_count
  local elapsed_seconds = opts.elapsed_seconds
  local status_text = opts.status_text or ""
  local status_color = opts.status_color
  local board_tint = opts.board_tint
  local fade = opts.fade or 0
  local blink = opts.blink or false
  local sparkles = opts.sparkles
  local paused = opts.paused or false
  local palette = opts.palette
  local empty_bg = board_tint or color.empty_color(palette)

  local buf = canvas.rasterize(tiles, {
    board_tint = board_tint,
    fade = fade,
    palette = palette,
  })

  if sparkles then
    for _, sp in ipairs(sparkles) do
      local r, c = sp.rc[1], sp.rc[2]
      local sp_color, ch = sp.color, sp.ch
      local x0 = GAP_X + c * (CELL_W + GAP_X)
      local y0 = GAP_Y + r * (CELL_H + GAP_Y)
      local cx = x0 + math.floor(CELL_W / 2)
      local cy = y0 + math.floor(CELL_H / 2)
      buf[cy + 1][cx + 1] = { ch, sp_color, empty_bg }
    end
  end

  local board_str = render_buffer(buf)

  local time_label = util.format_duration(elapsed_seconds) .. (paused and (" " .. PAUSE_SYMBOL) or "")
  local dim = "\x1b[38;2;150;150;150m"
  local header_lines = {
    centered_styled_line({
      { text = "2 0 4 8", style = "\x1b[1m\x1b[38;2;90;200;250m" },
      { text = "   Score: ", style = dim },
      { text = tostring(score), style = "\x1b[1m\x1b[38;2;255;215;0m" },
      { text = "   Best: ", style = dim },
      { text = tostring(best), style = "\x1b[38;2;180;180;180m" },
    }, BOARD_W),
    centered_styled_line({
      { text = "Moves: ", style = dim },
      { text = tostring(moves_count), style = "\x1b[38;2;150;200;150m" },
      { text = "   Time: ", style = dim },
      { text = time_label, style = "\x1b[38;2;180;200;255m" },
      { text = "   Palette: ", style = dim },
      { text = palette or "classic", style = "\x1b[38;2;150;170;220m" },
    }, BOARD_W),
  }

  local footer_lines = {
    centered_styled_line({
      { text = "Arrows/WASD: move", style = dim },
      { text = "   U: undo", style = dim },
      { text = "   P: palette", style = dim },
    }, BOARD_W),
    centered_styled_line({
      { text = "Space: pause", style = dim },
      { text = "   R: restart", style = dim },
      { text = "   Q: quit", style = dim },
    }, BOARD_W),
  }

  if status_text ~= "" then
    local sc = status_color or { 255, 80, 80 }
    footer_lines[#footer_lines + 1] = string.format(
      "\x1b[1m%s\x1b[38;2;%d;%d;%dm%s\x1b[0m\x1b[K",
      blink and "\x1b[5m" or "", sc[1], sc[2], sc[3], center_text(status_text, BOARD_W))
  else
    footer_lines[#footer_lines + 1] = "\x1b[K"
  end

  local out = {
    "\x1b[H", header_lines[1], header_lines[2], "\x1b[K", board_str, "",
  }
  for _, l in ipairs(footer_lines) do out[#out + 1] = l end
  out[#out + 1] = "\x1b[J"

  io.write(table.concat(out, "\n"))
  io.flush()
end

return M
