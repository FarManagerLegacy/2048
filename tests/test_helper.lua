local M = {}
local slash = package.config:sub(1, 1)
local windows = slash == "\\"

local function quote(path)
  return '"' .. path:gsub('"', '\\"') .. '"'
end

local function mkdir(path)
  local command = windows
    and ("mkdir " .. quote(path) .. " >nul 2>nul")
    or ("mkdir " .. quote(path) .. " >/dev/null 2>&1")
  local result = os.execute(command)
  return result == true or result == 0
end

local function rmdir(path)
  local command = windows
    and ("rmdir /s /q " .. quote(path) .. " >nul 2>nul")
    or ("rm -rf " .. quote(path) .. " >/dev/null 2>&1")
  local result = os.execute(command)
  if result ~= true and result ~= 0 then error("cannot remove temp directory: " .. path, 0) end
end

function M.new_temp_dir(prefix)
  local base = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "."
  prefix = prefix or "2048-test"
  for attempt = 1, 100 do
    local path = base .. slash .. prefix .. "_" .. os.time() .. "_" .. math.random(1, 2147483646) .. "_" .. attempt
    if mkdir(path) then
      local owned = true
      return {
        path = path,
        cleanup = function()
          if owned then owned = false; rmdir(path) end
        end,
      }
    end
  end
  error("cannot create unique temp directory in " .. base, 0)
end

return M
