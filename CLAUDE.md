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

The app is a Crystal + Raylib desktop application using an event-sourcing architecture.

**Data flow per frame:**

```
InfiniteCanvas.run (infinite_canvas.cr)
  └─ canvas.update   ← input handlers emit CanvasEvents → apply to @model → sync @elements
  └─ canvas.draw     ← Renderer reads @elements (arrows first, then shapes), draws selection/draft
  └─ draw_hud        ← overlay: tool name, element count, zoom level, undo/redo hints
```

**Event sourcing** (`model.cr`, `events.cr`, `apply.cr`, `history.cr`):

- `CanvasModel` is the authoritative state. `@elements : Array(Element)` is a derived view cache rebuilt by `sync_elements_from_model` after each event.
- All mutations go through `emit(event)` → `apply(@model, event)` → `@history.push(event)` → `sync_elements_from_model`. Text edits use `emit_text_event` (no sync, element is live editor) with a word-coalescing buffer.
- `HistoryManager` stores a serialised checkpoint + event log. Undo replays the log from the checkpoint with the last event removed. `Ctrl+Z` / `Ctrl+Y` / `Ctrl+Shift+Z`.

**Element hierarchy** (`element.cr`):

- `Element` — abstract base. Owns `bounds : R::Rectangle` (world space) and `id : UUID`. No draw methods — rendering is entirely in `Renderer`.
- `RectElement` — filled rect with centred multi-line label; `fit_content` / `min_size`.
- `TextElement` — plain text node, auto-sized with optional word wrap; exposes `visual_line_runs`, `cursor_visual_pos`, `visual_selection_ranges` for the renderer.
- `ArrowElement` — connects two elements by UUID; `compute_path` resolves endpoints and returns waypoints; `near_line?` uses those for hit-testing.

**Canvas state machine** (`canvas.cr`):

- `ActiveTool` — `Selection | Rect | Text | Arrow` (keys S / R / T / A)
- `DragMode` — `None | Drawing | Moving | Resizing | Connecting | Selecting`
- `@selected_id : UUID?` / `@selected_ids : Array(UUID)` — identity-stable selection; `@selected_index` is a derived index rebuilt after each sync
- `@text_session_id : UUID?` — tracks live text editing; `TextChangedEvent` / `InsertTextEvent` emitted at word boundaries or session commit

**Coordinate system:** all element positions are in world space. Convert with `R.get_screen_to_world_2d(mouse_screen, @camera)`. Zoom-invariant sizes (handles, selection outline, arrow hit threshold) are expressed as `pixels / @camera.zoom`.

**Rendering order:** arrows drawn first (behind shapes/text). `Renderer#draw_arrow_highlighted` used for selection overlay. Grid, elements, selection, and draft are all drawn inside `begin_mode_2d`.

**Persistence** (`model.cr`, `canvas.cr`): `Canvas#save` writes `@model.to_json` directly. On load, new-format files (with nested `bounds` object) are deserialised via `CanvasModel.from_json`; legacy flat-field files are migrated via `*ElementData` structs in `persistence.cr` and immediately re-saved in the new format.

**Known gaps** (see `TODO.md` for the full list):
- `handle_left_mouse` handles press / drag / release in one large method.
- Arrow routing (`compute_path`, `side_fraction`) is recomputed every frame with no cache.
