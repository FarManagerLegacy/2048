-- http://luacheck.readthedocs.io/en/stable/config.html
local lm = {std="_G+luamacro", new_read_globals={}}
local raw = {std="_G", new_read_globals={}}
files["main.lua"] = lm
files["2048.dev.lua"] = lm
files["2048.lua"] = lm
files["console/**/*.lua"] = {std="_G"}
files["tests/**/*.lua"] = raw

local options = {
  std = "_G+luafar";
  read_globals={"loader"};
  --exclude_files={};
  include_files={"**/*.lua"};
}

return options
