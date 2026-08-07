local _filename = far.GetReparsePointInfo((...))
local Info = Info or package.loaded.regscript or function(...) return ... end --luacheck: ignore 113/Info
local nfo = Info { _filename or ...,
  name        = "2048 dev";
  description = "Classic 2048 game implementation";
  version     = "0.1"; --https://semver.org/lang/ru/
  author      = "jd";
  url         = "https://forum.farmanager.com/viewtopic.php?t=13979";
  id          = "DF267EF5-8B5B-408C-A91B-64D76C78FCC2";
  disabled    = not _filename;
}
if not nfo or nfo.disabled then return end

local main = "@".._filename:match(".+[\\/]").."main.lua"
local function game()
	eval(main)
end

function nfo:execute() --luacheck: ignore 212/self
  game()
end

Macro { description="2048 dev";
  area="Common"; key="";
  id="CD531A3F-2342-4C5E-BB63-671C23BE8827";
  action=function()
    game()
  end;
}

MenuItem{
  guid="8CC0E4B7-9459-457E-9E00-E5069CAC7FC2";
  menu="Plugins";
  area="Common";
  text=function() return"2048 dev" end;
  action=function()
    game()
  end;
}
