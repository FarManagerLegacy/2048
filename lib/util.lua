-- Small color/number helpers.
local M = {}

M.now = os.clock

function M.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M.round(x)
  if x >= 0 then
    return math.floor(x + 0.5)
  end
  return -math.floor(-x + 0.5)
end

function M.trunc(x)
  return math.floor(x)
end

function M.bit_length(v)
  local n = 0
  while v > 0 do
    v = math.floor(v / 2)
    n = n + 1
  end
  return n
end

function M.blend(c1, c2, t)
  t = M.clamp(t, 0.0, 1.0)
  return {
    M.trunc(c1[1] + (c2[1] - c1[1]) * t),
    M.trunc(c1[2] + (c2[2] - c1[2]) * t),
    M.trunc(c1[3] + (c2[3] - c1[3]) * t),
  }
end

function M.lighten(c, amount)
  local out = {}
  for i = 1, 3 do
    local v = math.min(1.0, c[i] / 255 + amount)
    out[i] = M.trunc(v * 255)
  end
  return out
end

function M.format_duration(seconds)
  seconds = math.floor(math.max(0, seconds))
  local h = math.floor(seconds / 3600)
  local rem = seconds % 3600
  local m = math.floor(rem / 60)
  local s = rem % 60
  if h > 0 then
    return string.format("%02d:%02d:%02d", h, m, s)
  end
  return string.format("%02d:%02d", m, s)
end

function M.rgb_to_hsv(r, g, b)
  local maxc = math.max(r, g, b)
  local minc = math.min(r, g, b)
  local v = maxc
  if minc == maxc then
    return 0.0, 0.0, v
  end
  local s = (maxc - minc) / maxc
  local rc = (maxc - r) / (maxc - minc)
  local gc = (maxc - g) / (maxc - minc)
  local bc = (maxc - b) / (maxc - minc)
  local h
  if r == maxc then
    h = bc - gc
  elseif g == maxc then
    h = 2.0 + rc - bc
  else
    h = 4.0 + gc - rc
  end
  h = (h / 6.0) % 1.0
  return h, s, v
end

function M.hsv_to_rgb(h, s, v)
  if s == 0.0 then
    return v, v, v
  end
  local i = math.floor(h * 6.0)
  local f = (h * 6.0) - i
  local p = v * (1.0 - s)
  local q = v * (1.0 - s * f)
  local t = v * (1.0 - s * (1.0 - f))
  i = i % 6
  if i == 0 then return v, t, p end
  if i == 1 then return q, v, p end
  if i == 2 then return p, v, t end
  if i == 3 then return p, q, v end
  if i == 4 then return t, p, v end
  return v, p, q
end

return M
