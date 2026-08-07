## Architectural decisions

### Why animation is implemented as an FSM

- `animation_fsm.lua` encapsulates all intermediate states:
  - initial and final tile positions;
  - movement;
  - new-tile appearance.
- `console/render.lua` and `far/main.lua` consume only `animation:tiles()`
  and do not need to know the animation details.

### Why `far.Timer` plus `ACTL_SYNCHRO` instead of timed `DN_INPUT`

- FAR Manager is event-driven; the main loop must not be blocked.
- `far.Timer` creates periodic events that enter FAR's main loop through
  `ACTL_SYNCHRO` and invoke the Lua callback.
- The timer is created once, disabled (`Enabled = false`) outside animations,
  and enabled only while a move animation is active.

### Why `FRAMES_PER_TICK` lives in FAR config

- Different terminals (FAR with ConPTY, FAR with conhost, and other emulators)
  render at different speeds.
- Tuning `FRAMES_PER_TICK` keeps animation smooth without issuing
  `DM_REDRAW` too frequently.

### Why status colors use `DN_CTLCOLORDLGITEM`

- FAR does not allow changing a `DI_TEXT` color through `DM_SETTEXTPTR`.
- `DN_CTLCOLORDLGITEM` is FAR's standard mechanism for assigning control
  colors before drawing.
- FAR color indexes are used here (2 = green, 4 = red), together with
  `FCF_FLASH` for blinking.
