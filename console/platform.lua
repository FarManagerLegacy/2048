-- Shared console facade: ANSI screen control and key decoding stay portable.
local ffi = require("ffi")

local backend
if ffi.os == "Windows" then
  backend = loader("console/winapi")
elseif ffi.os == "Linux" then
  backend = loader("console/linuxapi")
else
  error("console frontend supports only Windows and Linux (ffi.os == '" .. ffi.os .. "')")
end

local M = {}
local KEY_MAP = {
  [string.byte("w")] = "up", [string.byte("W")] = "up",
  [string.byte("a")] = "left", [string.byte("A")] = "left",
  [string.byte("s")] = "down", [string.byte("S")] = "down",
  [string.byte("d")] = "right", [string.byte("D")] = "right",
  [string.byte("u")] = "undo", [string.byte("U")] = "undo",
  [string.byte("p")] = "palette", [string.byte(" ")] = "pause",
  [string.byte("r")] = "restart", [string.byte("R")] = "restart",
  [string.byte("q")] = "quit", [string.byte("Q")] = "quit", [0x1b] = "quit",
}
local WINDOWS_ARROWS = { [0x48] = "up", [0x50] = "down", [0x4b] = "left", [0x4d] = "right" }
local LINUX_ARROWS = { [0x41] = "up", [0x42] = "down", [0x43] = "right", [0x44] = "left" }

function M.prepare_console() return backend.prepare() end
function M.restore_console() return backend.restore() end

function M.enter_alternate_screen()
  io.write("\x1b[?1049h\x1b[H")
  io.flush()
end

function M.leave_alternate_screen()
  io.write("\x1b[?1049l")
  io.flush()
end

function M.sleep(seconds) return backend.sleep(seconds) end
function M.now() return backend.now() end
function M.kbhit() return backend.kbhit() end
function M.flush_input() return backend.flush_input() end
function M.read_byte(timeout_ms) return backend.read_byte(timeout_ms == nil and -1 or timeout_ms) end

function M._decode_key(first_byte, read_next)
  if first_byte == nil then return nil end
  if backend.is_windows and (first_byte == 0xe0 or first_byte == 0x00) then
    return WINDOWS_ARROWS[read_next(-1)]
  end
  if not backend.is_windows and first_byte == 0x1b then
    local prefix = read_next(25)
    if prefix ~= 0x5b and prefix ~= 0x4f then return "quit" end
    return LINUX_ARROWS[read_next(25)] or "quit"
  end
  return KEY_MAP[first_byte]
end

function M.read_key()
  return M._decode_key(backend.read_byte(-1), backend.read_byte)
end

return M
