-- Windows FFI bindings: console ANSI mode, raw keyboard input (msvcrt),
-- sleep, and a high-resolution wall-clock timer.
local ffi = require("ffi")
local bit = require("bit")

if ffi.os ~= "Windows" then
  error("winapi.lua only supports Windows (ffi.os == '" .. ffi.os .. "')")
end

ffi.cdef([[
typedef int BOOL;
typedef unsigned long DWORD;
typedef void *HANDLE;

BOOL GetConsoleMode(HANDLE hConsoleHandle, DWORD *lpMode);
BOOL SetConsoleMode(HANDLE hConsoleHandle, DWORD dwMode);
BOOL SetConsoleOutputCP(unsigned int wCodePageID);
HANDLE GetStdHandle(DWORD nStdHandle);
void Sleep(DWORD dwMilliseconds);

BOOL QueryPerformanceCounter(int64_t *lpPerformanceCount);
BOOL QueryPerformanceFrequency(int64_t *lpFrequency);

int _kbhit(void);
int _getch(void);
]])

local C = ffi.C
local M = {}

local STD_OUTPUT_HANDLE = -11
local ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004

function M.enable_windows_ansi()
  C.SetConsoleOutputCP(65001)
  local handle = C.GetStdHandle(STD_OUTPUT_HANDLE)
  local mode = ffi.new("DWORD[1]")
  if C.GetConsoleMode(handle, mode) == 0 then
    return
  end
  local new_mode = bit.bor(mode[0], ENABLE_VIRTUAL_TERMINAL_PROCESSING)
  C.SetConsoleMode(handle, new_mode)
end

function M.enter_alternate_screen()
  io.write("\x1b[?1049h\x1b[H")
  io.flush()
end

function M.leave_alternate_screen()
  io.write("\x1b[?1049l")
  io.flush()
end

function M.sleep(seconds)
  C.Sleep(math.floor(seconds * 1000 + 0.5))
end

local qpc_freq = ffi.new("int64_t[1]")
C.QueryPerformanceFrequency(qpc_freq)
local freq = tonumber(qpc_freq[0])

function M.now()
  local counter = ffi.new("int64_t[1]")
  C.QueryPerformanceCounter(counter)
  return tonumber(counter[0]) / freq
end

function M.kbhit()
  return C._kbhit() ~= 0
end

function M.flush_input()
  while C._kbhit() ~= 0 do
    C._getch()
  end
end

local function getch_byte()
  return C._getch()
end
M._getch_byte = getch_byte

local ARROW_PREFIX = { [0xe0] = true, [0x00] = true }
local ARROW_MAP = { [0x48] = "up", [0x50] = "down", [0x4b] = "left", [0x4d] = "right" }
local WASD_MAP = {
  [string.byte("w")] = "up", [string.byte("s")] = "down",
  [string.byte("a")] = "left", [string.byte("d")] = "right",
  [string.byte("W")] = "up", [string.byte("S")] = "down",
  [string.byte("A")] = "left", [string.byte("D")] = "right",
}

function M.read_key()
  local ch = getch_byte()
  if ARROW_PREFIX[ch] then
    local ch2 = getch_byte()
    return ARROW_MAP[ch2]
  end
  if WASD_MAP[ch] then
    return WASD_MAP[ch]
  end
  if ch == string.byte("u") or ch == string.byte("U") then
    return "undo"
  end
  if ch == string.byte("p") then
    return "palette"
  end
  if ch == string.byte(" ") then
    return "pause"
  end
  if ch == string.byte("r") or ch == string.byte("R") then
    return "restart"
  end
  if ch == string.byte("q") or ch == string.byte("Q") or ch == 0x1b then
    return "quit"
  end
  return nil
end

return M
