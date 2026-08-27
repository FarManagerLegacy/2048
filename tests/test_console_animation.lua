local root_loader = dofile("loader.lua")()
local T = root_loader("tests/test_runner")

local clock = 0
local delay_remaining
local render_seconds = 0.1
local advances = {}
local phase = {
  step = 0,
  total_steps = 5,
  done = false,
}
local function reset_phase(total_steps)
  clock, advances = 0, {}
  phase.step, phase.total_steps, phase.done = 0, total_steps, false
end
function phase:advance(n)
  advances[#advances + 1] = n
  self.step = math.min(self.total_steps, self.step + n)
  self.done = self.step >= self.total_steps
end
function phase:is_done() return self.done end
function phase.tiles() return {} end

local animation = {
  phases = { phase },
  phase_idx = 1,
}
function animation.is_done() return phase:is_done() end
function animation.advance() end

local stubs = {
  ["lib/animation_fsm"] = {
    new_move_animation = function() return animation end,
    new_merge_pop = function() return phase end,
    new_spawn_fade = function() return phase end,
    slide_duration = function() return 0.08 end,
    next_frame_delay = function(deadline, remaining)
      delay_remaining = remaining
      return math.max(0, (deadline - clock) / remaining)
    end,
  },
  ["console/platform"] = {
    now = function() return clock end,
    sleep = function(seconds) clock = clock + seconds end,
  },
  ["console/render"] = {
    render_frame = function() clock = clock + render_seconds end,
  },
  ["lib/constants"] = {
    ANIM_FRAME_DELAY = 0.016,
    MERGE_POP_DELAY = 0.02,
    SPAWN_FADE_DELAY = 0.016,
  },
}
loader = function(name) return stubs[name] or root_loader(name) end
local chunk = assert(loadfile("console/animation.lua"))
setfenv(chunk, setmetatable({ loader = loader }, { __index = _G }))
local console_animation = chunk()

T.describe("console animation pacing", function()
  local function assert_catches_up(run)
    reset_phase(5)
    delay_remaining = nil
    run()
    T.eq(advances[1], 1)
    T.ok(delay_remaining == nil or delay_remaining == 4)
    T.ok(advances[2] >= 4)
  end

  T.it("catches up slide frames after a slow render", function()
    assert_catches_up(function()
      console_animation.play_move({}, {}, {}, nil, {}, "classic")
    end)
  end)

  T.it("does not double-count elapsed slide frames", function()
    reset_phase(5)
    render_seconds = 0.01
    console_animation.play_move({}, {}, {}, nil, {}, "classic")
    render_seconds = 0.1
    T.ok(advances[3] < 3)
  end)

  T.it("catches up merge-pop frames after a slow render", function()
    assert_catches_up(function()
      console_animation.animate_merge_pop({}, {}, 0, 0, 0, 0, "classic")
    end)
  end)

  T.it("catches up spawn-fade frames after a slow render", function()
    assert_catches_up(function()
      console_animation.animate_spawn_fadein({}, {}, 0, 0, 0, 0, "classic")
    end)
  end)
end)

T.summary_and_exit()
