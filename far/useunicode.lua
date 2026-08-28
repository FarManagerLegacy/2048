-- "Reliable Unicode rendering relies on Font Linking / Fallback, a feature conhost lacked until Windows 11."
local ffi = require("ffi")
if ffi.os ~= "Windows" then return true, "not Windows" end
if not win then return true, "no FAR" end

ffi.cdef[[
typedef unsigned long DWORD;
typedef void* HANDLE;
typedef void* HWND;

HANDLE __stdcall CreateToolhelp32Snapshot(DWORD dwFlags, DWORD th32ProcessID);
int __stdcall Process32First(HANDLE hSnapshot, void *lppe);
int __stdcall Process32Next(HANDLE hSnapshot, void *lppe);
int __stdcall CloseHandle(HANDLE hObject);
DWORD __stdcall GetCurrentProcessId(void);

HWND __stdcall GetConsoleWindow(void);
int __stdcall GetClassNameA(HWND hWnd, char *lpClassName, int nMaxCount);
]]

local C = ffi.C
local function get_console_class()
  local hwnd = C.GetConsoleWindow()
  if hwnd == nil then return nil end

  local buffer = ffi.new("char[256]")
  local length = C.GetClassNameA(hwnd, buffer, 256)
  if length == 0 then return nil end

  return ffi.string(buffer, length)
end

local CurrentBuild = win.GetRegKey("HKLM", [[SOFTWARE\Microsoft\Windows NT\CurrentVersion]], "CurrentBuild")
if CurrentBuild and CurrentBuild > "22000" then
  return true, CurrentBuild -- Windows 11
end

local console_class = get_console_class()
if console_class ~= "ConsoleWindowClass" then
  return true, console_class -- PseudoConsoleWindow
end

if os.getenv("TERM_PROGRAM") or os.getenv("ConEmuPID") then
  return true, "known-terminal"
end

local UseDX = win.GetRegKey("HKCU", "Console", "UseDX")
if UseDX then
  return true, UseDX -- openconsole
end

return false, "conhost"
