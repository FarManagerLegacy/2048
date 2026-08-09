local Info = Info or package.loaded.regscript or function(...) return ... end --luacheck: ignore 113/Info
local nfo = Info { _filename or ...,
  name        = "2048";
  description = "Classic 2048 game implementation";
  version     = "0.2"; --https://semver.org/lang/ru/
  author      = "jd";
  url         = "https://forum.farmanager.com/viewtopic.php?t=13979";
  id          = "79CC0BD9-0AAB-4714-92BE-2E92C3C54DC0";
  --minfarversion = {3,0,0,4744,0};
  --execute     = function(nfo,name) end;
  --options     = {
  --};
  --disabled    = true;
}
if not nfo or nfo.disabled then return end
--local O = nfo.options

local function getLoader(macrofile)
  local loader_lua = "loader.lua"
  local arg0 = Macro and macrofile or _filename or arg and arg[0]
  local dir
  if arg0 then
    arg0 = far and far.GetReparsePointInfo(arg0) or arg0
    dir = arg0:match("(.+)[\\/]")
    if dir then loader_lua = dir..package.config:sub(1,1)..loader_lua end
  end
  return dofile(loader_lua)(dir)
end

local loader = loader or getLoader(...) --luacheck: read_globals loader, ignore 411/loader

if not far then
  return loader("console/main")()
end

local game = loader("far/main")

if _filename then
  return game()
end

function nfo:execute() --luacheck: ignore 212/self
  game()
end

Macro { description="2048";
  area="Common"; key="";
  id="E670234E-AFCC-49E9-A2A7-C8DDC5DA3102";
  action=function()
    game()
  end;
}

MenuItem{
  guid="A49F8EBD-FB64-47EA-B753-55688ECF5876";
  menu="Plugins";
  area="Common";
  text=function() return"2048" end;
  action=function()
    game()
  end;
}
