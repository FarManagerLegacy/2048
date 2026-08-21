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
  if type(b) ~= "table" or #b == 0 or type(b[1]) ~= "table" or #b[1] == 0 then return false end
  local width = #b[1]
  for _, row in ipairs(b) do
    if type(row) ~= "table" or #row ~= width then return false end
    for _, value in ipairs(row) do
      if type(value) ~= "number" or value < 0 or value % 1 ~= 0 then return false end
    end
  end
  return true, width, #b
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
  local valid = type(state) == "table" and valid_board(state.board)
  if not valid then
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
  local f, open_err = io.open(M.SAVE_PATH, "r")
  if not f then
    if os.rename(M.SAVE_PATH, M.SAVE_PATH) then
      return nil, "Save read error: " .. tostring(open_err)
    end
    return nil, nil
  end
  local contents = f:read("*a")
  f:close()

  local chunk, syntax_err = loadstring("return " .. contents)
  if not chunk then return nil, "Save syntax error: " .. tostring(syntax_err) end
  if chunk then setfenv(chunk, {}) end
  local ok, data = pcall(chunk)
  if not ok then return nil, "Save format error: " .. tostring(data) end
  if type(data) ~= "table" then return nil, "Save format error: expected a table" end

  data.game = data.game or "2048"
  if data.game ~= "2048" then return nil, "Unsupported game in save: " .. tostring(data.game) end
  local b = data.board
  local valid, width, height = valid_board(b)
  if not valid then return nil, "Invalid board format in save" end
  for _, field in ipairs({ "score", "best", "moves_count" }) do
    local value = data[field]
    if value ~= nil and (type(value) ~= "number" or value < 0 or value % 1 ~= 0) then
      return nil, "Invalid numeric field " .. field
    end
  end
  local elapsed = data.elapsed_seconds
  if elapsed ~= nil and (type(elapsed) ~= "number" or elapsed < 0
      or elapsed ~= elapsed or elapsed == math.huge or elapsed == -math.huge) then
    return nil, "Invalid numeric field elapsed_seconds"
  end
  constants.set_board_dimensions(width, height)
  return data
end

function M.clear_save()
  os.remove(M.SAVE_PATH)
end

return M
