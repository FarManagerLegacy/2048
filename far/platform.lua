return {
  now = win.Clock --luacheck: read_globals win.Clock
    or function() return far.FarClock() / 1000000 end
}
