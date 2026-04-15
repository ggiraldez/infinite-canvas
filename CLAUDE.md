# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

Raylib is built locally under `local/lib/`. Inline the library path when building:

```sh
LIBRARY_PATH=$PWD/local/lib shards build
# or for a release build:
LIBRARY_PATH=$PWD/local/lib shards build --release
```

Run the binary (also needs the runtime path):

```sh
LD_LIBRARY_PATH=$PWD/local/lib ./bin/infinite_canvas
```

There are no tests and no linter configured. Type-checking is done implicitly by `shards build`.

## Architecture

The app is a Crystal + Raylib desktop application. Four source files; no frameworks.

**Data flow per frame:**

```
InfiniteCanvas.run (infinite_canvas.cr)
  └─ canvas.update   ← input: pan, zoom, mouse, keyboard, tool switch
  └─ canvas.draw     ← render: grid, elements (arrows first, then shapes), selection, draft
  └─ draw_hud        ← overlay: tool name, element count, zoom level
```

**Element hierarchy** (`element.cr`):

- `Element` — abstract base. Owns `bounds : R::Rectangle` (world space) and `id : UUID`.
- `RectElement` — filled rect with centred multi-line label; resizable.
- `TextElement` — plain text, no background; always sized to content, not resizable.
- `ArrowElement` — connects two elements by UUID. Holds a reference to the canvas `@elements` array so it can resolve endpoints at draw-time without coupling to `Canvas`. `contains?` always returns false; `Canvas#hit_test_element` calls `near_line?(point, threshold)` instead with a zoom-aware screen-pixel threshold.

**Canvas state machine** (`canvas.cr`):

- `ActiveTool` — `Selection | Rect | Text | Arrow` (keys S / R / T / A)
- `DragMode` — `None | Drawing | Moving | Resizing | Connecting`
- `@selected_index : Int32?` — index into `@elements`; single selection only
- `@arrow_source_index : Int32?` — set while `DragMode::Connecting` is active

**Coordinate system:** all element positions are in world space. Convert with `R.get_screen_to_world_2d(mouse_screen, @camera)`. Zoom-invariant sizes (handles, selection outline, arrow hit threshold) are expressed as `pixels / @camera.zoom`.

**Rendering order:** arrows are drawn before shapes/text so they appear behind them. `draw_selection` special-cases `ArrowElement` to highlight the line instead of drawing a bounding-rect outline.

**Persistence** (`persistence.cr`): on exit, `Canvas#save` serialises every element to `canvas.json` via `*ElementData` mirror structs (one per concrete type). On load, the `"type"` field dispatches to the right deserialiser. `ArrowElementData#to_element` requires the live `@elements` array so the arrow can hold a reference to it — call `to_element(@elements)` not `to_element`.

**Known architectural gaps** (see `TODO.md` for the full list):
- `Element` has no `abstract def to_data`, so `Canvas#save` still has a manual `case` switch per type.
- `@selected_index` is a fragile array index, not an object reference.
- `handle_left_mouse` handles all three mouse phases (press / held / release) in one 90-line method.
