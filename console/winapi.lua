-- Windows console backend: FFI bindings, timing, and raw keyboard bytes.
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
local M = { is_windows = true }
local STD_OUTPUT_HANDLE = -11
local ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004

function M.prepare()
  C.SetConsoleOutputCP(65001)
  local handle = C.GetStdHandle(STD_OUTPUT_HANDLE)
  local mode = ffi.new("DWORD[1]")
  if C.GetConsoleMode(handle, mode) == 0 then return end
  C.SetConsoleMode(handle, bit.bor(mode[0], ENABLE_VIRTUAL_TERMINAL_PROCESSING))
end

function M.restore() return true end

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
  while C._kbhit() ~= 0 do C._getch() end
end

function M.read_byte(_)
  return C._getch()
end

return M
