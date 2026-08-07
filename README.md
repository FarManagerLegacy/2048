# 2048

Classic 2048 implementations for LuaJIT, with tile movement and spawn animations,
switchable color palettes, save/load support, undo history, and statistics.

## Frontends

- **Lua console** — Windows console frontend using ANSI output and LuaJIT FFI.
- **FAR Manager** — native FAR dialog frontend.

The shared Lua code in `lib/` has no dependency on console I/O, FAR APIs, or FFI.
Native dependencies are limited to the runtime features required by each frontend.

## Run

From the repository root:

```text
luajit main.lua
python 2048.py
```

The Lua entrypoint selects the console frontend. To run the FAR frontend,
launch `far/main.lua` through FAR Manager's LuaMacro environment.


## Single-file Lua bundles

Build the FAR bundle from the repository root:

```text
luajit loader.lua main.lua
```

The bundle is written to the current directory as `main.bundle.lua`.
Pass a second argument to choose its name:

```text
luajit loader.lua main.lua 2048.lua
```

Bundling is integrated into loader.lua and is activated when an entrypoint argument is present.
It resolves every module through the same project loader as the source entrypoint;
a missing module stops the bundling command with an error.

## Tests

Run the complete Lua test suite with one command:

```text
luajit tests/run_all.lua
```

Individual Lua test files can also be run directly when debugging a focused area:

```text
luajit tests/test_core.lua
```
