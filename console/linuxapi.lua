-- Linux console backend: libc timing, polling, and terminal raw mode.
local ffi = require("ffi")

if ffi.os ~= "Linux" then
  error("linuxapi.lua only supports Linux (ffi.os == '" .. ffi.os .. "')")
end

ffi.cdef([[
typedef unsigned long nfds_t;
typedef long ssize_t;
struct pollfd { int fd; short events; short revents; };
struct timespec { long tv_sec; long tv_nsec; };
int poll(struct pollfd *fds, nfds_t nfds, int timeout);
ssize_t read(int fd, void *buf, size_t count);
int usleep(unsigned int usec);
int clock_gettime(int clk_id, struct timespec *tp);
]])

local C = ffi.C
local M = { is_windows = false }
local POLLIN = 0x0001
local CLOCK_MONOTONIC = 1
local pollfd = ffi.new("struct pollfd[1]")
local buffer = ffi.new("uint8_t[1]")
pollfd[0].fd = 0
pollfd[0].events = POLLIN
local saved_state

local function succeeded(result)
  return result == true or result == 0
end

function M.prepare()
  local pipe = io.popen("stty -g 2>/dev/null")
  local state = pipe and pipe:read("*l")
  if pipe then pipe:close() end
  if not state or not state:match("^[%da-fA-F:]+$") then
    error("console frontend requires an interactive TTY (stty -g failed)")
  end
  saved_state = state
  if not succeeded(os.execute("stty -echo -icanon min 0 time 0 2>/dev/null")) then
    error("console frontend could not enable raw terminal input")
  end
end

function M.restore()
  if not saved_state then return true end
  local state = saved_state
  saved_state = nil
  if not succeeded(os.execute("stty " .. state .. " 2>/dev/null")) then
    return nil, "could not restore terminal settings"
  end
  return true
end

function M.sleep(seconds)
  C.usleep(math.floor(math.max(seconds, 0) * 1000000 + 0.5))
end

function M.now()
  local ts = ffi.new("struct timespec[1]")
  assert(C.clock_gettime(CLOCK_MONOTONIC, ts) == 0, "clock_gettime failed")
  return tonumber(ts[0].tv_sec) + tonumber(ts[0].tv_nsec) / 1000000000
end

function M.kbhit()
  return C.poll(pollfd, 1, 0) > 0
end

function M.flush_input()
  while M.kbhit() do
    if C.read(0, buffer, 1) ~= 1 then break end
  end
end

function M.read_byte(timeout_ms)
  if C.poll(pollfd, 1, timeout_ms) <= 0 then return nil end
  if C.read(0, buffer, 1) ~= 1 then return nil end
  return tonumber(buffer[0])
end

return M
