local function assert_normalized(path)
  local err = path:match("\\") -- backslash
    or path:match("//+") -- doubleslash
    or path:match("^/") or path:match("/$") -- starts or end with slash
    or path:match("^%.+/") or path:match("/%.+/") or path:match("/%.+$") or path:match("^%.+$") --relative reference
  if err then
    error(("Path validation failed (contains '%s'): %s"):format(err, path), 3)
  end
end

local function module_path(name, root)
  assert(type(name) == "string", "loader path expects a string")
  assert_normalized(name)
  local slash = package.config:sub(1,1)
  if slash=="\\" then name = name:gsub("/","\\") end
  if root then name = root..slash..name end
  return name.. ".lua"
end

local function make_loader(root)
  local cached = {}
  local LOADING_MARKER = {} -- Sentinel value

  local function resolve_module_path(name)
    return module_path(name, root)
  end

  local function load_module(name)
    local path = resolve_module_path(name)
    local state = cached[path]

    if state == LOADING_MARKER then error("cyclic module load: " .. name, 2) end
    if state ~= nil then return state end

    local file = assert(io.open(path, "rb")); file:close()

    cached[path] = LOADING_MARKER

    local chunk, err = loadfile(path)
    if not chunk then
      cached[path] = nil
      error(err, 2)
    end

    setfenv(chunk, setmetatable({ loader = load_module }, { __index = _G }))

    local ok, result = pcall(chunk)
    if not ok then
      cached[path] = nil
      error(result, 2)
    end

    cached[path] = result == nil and true or result
    return cached[path]
  end

  return load_module, resolve_module_path
end

local function make_bundle(entry, output, root)
  local function normalize(path)
    local parts = {}
    for part in path:gsub("\\", "/"):gmatch("[^/]+") do
      if part == ".." then
        if #parts > 0 and parts[#parts] ~= ".." then table.remove(parts) else parts[#parts + 1] = part end
      elseif part ~= "." then
        parts[#parts + 1] = part
      end
    end
    local result = table.concat(parts, "/")
    return result == "" and "." or result
  end

  local function exists(path)
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
  end

  local function read(path)
    local file, err = io.open(path, "rb")
    if not file then error(err, 0) end
    local source = file:read("*a")
    file:close()
    return source
  end

  local function module_id(name)
    return normalize(name:gsub("\\", "/"):gsub("%.lua$", ""))
  end

  local function imports(source)
    local names = {}
    for line in source:gmatch("[^\r\n]*\r?\n?") do
      if line == "" then break end
      if not line:match("^%s*%-%-") then
        for name in line:gmatch('loader%s*%(%s*"([^"]+)"%s*%)') do
          names[#names + 1] = name
        end
      end
    end
    return names
  end

  local entry_path = normalize(entry)
  local modules, seen, visiting = {}, {}, {}

  local function visit(name)
    local id = module_id(name)
    if seen[id] then return end
    if visiting[id] then error("cyclic module load: " .. id, 0) end
    local path = module_path(name, root)
    if not exists(path) then
      error("module not found: " .. id .. " (loader resolved " .. tostring(path) .. ")", 0)
    end
    visiting[id] = true
    local source = read(path)
    local dependencies = imports(source, path)
    for _, dependency in ipairs(dependencies) do visit(dependency) end
    visiting[id] = nil
    seen[id] = true
    modules[#modules + 1] = {
      id = id,
      source = source,
      has_loader = #dependencies > 0,
    }
  end

  for _, dependency in ipairs(imports(read(entry_path), entry_path)) do visit(dependency) end

  output = output or entry_path:match("[^/]+$"):gsub("%.lua$", ".bundle.lua")
  output = output:gsub("\\\\", "/"):match("([^/]+)$")
  local out = assert(io.open(output, "wb"))
  local function emit(line) out:write(line, "\n") end

  emit("local __modules, __cached = {}, {}")
  for _, module in ipairs(modules) do
    emit("__modules[" .. string.format("%q", module.id) .. "] = function" ..
      (module.has_loader and "(loader)" or "()"))
    out:write(module.source)
    if module.source:sub(-1) ~= "\n" then out:write("\n") end
    emit("end")
  end
  out:write([=[local function __bundle_load(name)
  if __cached[name] ~= nil then return __cached[name] end
  local result = __modules[name](__bundle_load)
  __cached[name] = result == nil and true or result
  return __cached[name]
end
local loader = __bundle_load]=], "\n")

  local source = read(entry_path)
  for line in source:gmatch("[^\r\n]*\r?\n?") do
    if line == "" then break end
    out:write(line)
  end
  out:close()
  return output
end

if arg and arg[1] then
  print(make_bundle(arg[1], arg[2], arg[3]))
end

return make_loader
