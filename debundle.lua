local function fail(message)
  error("invalid bundle: " .. message, 0)
end

local function read(path)
  local file, err = io.open(path, "rb")
  if not file then fail(err or ("cannot read " .. path)) end
  local source = file:read("*a")
  file:close()
  return source
end

local function write(path, source)
  local file, err = io.open(path, "wb")
  if not file then fail(err or ("cannot write " .. path)) end
  file:write(source)
  file:close()
end

local function valid_id(id)
  if id == "" or id:find("\\", 1, true) or id:find(":", 1, true)
    or id:find("\0", 1, true) or id:find("\r", 1, true) or id:find("\n", 1, true)
    or id:sub(1, 1) == "/" or id:sub(-1) == "/" then
    return false
  end
  for part in id:gmatch("[^/]+") do
    if part == "." or part == ".." then return false end
  end
  return not id:find("//", 1, true)
end

local function ensure_dir(path)
  local slash = package.config:sub(1, 1)
  local quoted = path:gsub('"', '\\"')
  local command = slash == "\\"
    and ('if not exist "' .. quoted .. '" mkdir "' .. quoted .. '" >nul 2>nul')
    or ('mkdir -p "' .. quoted .. '" >/dev/null 2>&1')
  local result = os.execute(command)
  if result ~= true and result ~= 0 then fail("cannot create output directory: " .. path) end
end

local function join(root, id)
  local slash = package.config:sub(1, 1)
  return root .. slash .. id:gsub("/", slash)
end

local mini_loader = [=[
local function __main_directory()
  local path = _filename or arg[0]:gsub("\\", "/")
  local directory = path:match("^(.*)/[^/]*$") or "."
  return directory:gsub("/", package.config:sub(1, 1))
end

local function __make_loader(root)
  local cached = {}
  local function load_module(name)
    local slash = package.config:sub(1, 1)
    local path = root .. slash .. name:gsub("/", slash) .. ".lua"
    if cached[name] ~= nil then return cached[name] end
    local chunk = assert(loadfile(path))
    setfenv(chunk, setmetatable({ loader = load_module }, { __index = _G }))
    local result = chunk()
    cached[name] = result == nil and true or result
    return cached[name]
  end
  return load_module
end

local loader = __make_loader(__main_directory())
]=]

local function debundle(bundle, output)
  local source = read(bundle)
  local header = "local __modules, __cached = {}, {}\n"
  if source:sub(1, #header) ~= header then fail("missing __modules header") end
  local position = #header + 1
  local modules = {}
  local seen_ids = {}
  local loader_marker = "local function __bundle_load(name)\n"
  while true do
    local marker_start, marker_end, id, factory = source:find(
      '__modules%["([^"]+)"%] = function%((%w*)%)\n', position)
    if not marker_start then break end
    if factory ~= "" and factory ~= "loader" then fail("unsupported module factory") end
    if not valid_id(id) then fail("unsafe module id: " .. id) end
    if seen_ids[id] then fail("duplicate module id: " .. id) end
    seen_ids[id] = true
    local body_start = marker_end + 1
    local body_end
    local cursor = body_start
    while true do
      local candidate = source:find("\nend\n", cursor, true)
      if not candidate then fail("unterminated module: " .. id) end
      local after = candidate + 5
      if source:sub(after, after + 10):match("^__modules%[")
        or source:sub(after, after + #loader_marker - 1) == loader_marker then
        body_end = candidate
        position = after
        break
      end
      cursor = candidate + 1
    end
    modules[#modules + 1] = { id = id, source = source:sub(body_start, body_end) }
  end

  if source:sub(position, position + #loader_marker - 1) ~= loader_marker then
    fail("missing generated bundle loader")
  end
  local tail_marker = "local loader = __bundle_load\n"
  local tail_start = source:find(tail_marker, position, true)
  if not tail_start then fail("missing bundle loader tail") end
  local entry = source:sub(tail_start + #tail_marker)

  ensure_dir(output)
  for _, module in ipairs(modules) do
    local path = join(output, module.id .. ".lua")
    local parent = path:match("^(.*)[/\\][^/\\]+$")
    if parent then ensure_dir(parent) end
    write(path, module.source)
  end
  write(join(output, "main.lua"), mini_loader .. "\n" .. entry)
  return output
end

if not arg or not arg[1] then
  io.stderr:write("usage: luajit debundle.lua <bundle.lua> [output-dir]\n")
  os.exit(2)
end

print(debundle(arg[1], arg[2] or "unpacked"))

return debundle
