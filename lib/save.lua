-- Save/load persistence for game state as a small Lua table.
local board_mod = loader("lib/board")

local M = {}

local function save_dir()
  local profile = win and win.GetEnv("FARLOCALPROFILE") or ""
  if profile and profile ~= "" then
    return profile
  end
  return "."
end

M.SAVE_PATH = save_dir() .. "/2048.save"

local function serialize(value)
  local kind = type(value)
  if kind == "number" or kind == "boolean" then return tostring(value) end
  if kind == "string" then return string.format("%q", value) end
  if kind ~= "table" then error("unsupported value: " .. kind) end

  local fields = {}
  if #value > 0 then
    for _, item in ipairs(value) do
      fields[#fields + 1] = serialize(item)
    end
    return "{" .. table.concat(fields, ",") .. "}"
  end
  for key, item in pairs(value) do
    fields[#fields + 1] = key .. "=" .. serialize(item)
  end
  return "{" .. table.concat(fields, ",") .. "}"
end

function M.save_state(state)
  if type(state) ~= "table" or type(state.board) ~= "table" then
    return false
  end
  local data = {
    board = state.board,
    score = state.score,
    best = state.best,
    moves_count = state.moves_count,
    palette = state.palette or "classic",
    elapsed_seconds = state.elapsed_seconds,
  }
  local f = io.open(M.SAVE_PATH, "w")
  if not f then return false end
  local ok, encoded = pcall(serialize, data)
  if not ok then f:close(); return false end
  f:write(encoded)
  f:close()
  return true
end

function M.load_state()
  local f = io.open(M.SAVE_PATH, "r")
  if not f then return nil end
  local contents = f:read("*a")
  f:close()

  local chunk = loadstring("return " .. contents)
  if chunk then setfenv(chunk, {}) end
  local ok, data = false, nil
  if chunk then ok, data = pcall(chunk) end
  if not ok or type(data) ~= "table" then return nil end

  local b = data.board
  if type(b) ~= "table" or #b ~= board_mod.BOARD_SIZE then return nil end
  for _, row in ipairs(b) do
    if type(row) ~= "table" or #row ~= board_mod.BOARD_SIZE then return nil end
  end
  return data
end

function M.clear_save()
  os.remove(M.SAVE_PATH)
end

return M
