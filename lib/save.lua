-- Save/load persistence for game state as a small Lua table.
local constants = loader("lib/constants")

local M = {}

local function save_dir()
  local profile = win and win.GetEnv("FARLOCALPROFILE") or os.getenv("FARLOCALPROFILE")
  if profile and profile ~= "" then
    return profile
  end
  return "."
end

M.SAVE_PATH = save_dir() .. "/2048.save"

local function valid_board(b)
  if type(b) ~= "table" or #b ~= constants.BOARD_HEIGHT then return false end
  for _, row in ipairs(b) do
    if type(row) ~= "table" or #row ~= constants.BOARD_WIDTH then return false end
    for _, value in ipairs(row) do
      if type(value) ~= "number" or value < 0 or value % 1 ~= 0 then return false end
    end
  end
  return true
end

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
  if type(state) ~= "table" or not valid_board(state.board) then
    return false
  end
  local data = {
    game = "2048",
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

  if data.game ~= "2048" then return nil end
  local b = data.board
  if not valid_board(b) then return nil end
  return data
end

function M.clear_save()
  os.remove(M.SAVE_PATH)
end

return M
