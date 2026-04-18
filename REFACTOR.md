# Event Sourcing Refactor — Incremental Plan

## Overview

Full conversion of the canvas from direct-mutation + Raylib-coupled elements to:

- **Pure model layer** — Crystal structs, no Raylib dependency, fully testable
- **Event sourcing** — all mutations are events applied to the model; state = checkpoint + event log
- **Layout pass** — word-wrap and arrow routing computed from model, cached between frames
- **Renderer** — pure presentation layer reading model + layout cache
- **History manager** — checkpoint + event log → undo/redo + future undo-tree support

## Current Status

- [x] Phase 0 — Write plan to `/workspace/REFACTOR.md`
- [x] Phase 1 — Pure model types (`src/model.cr`)
- [x] Phase 2 — Events + apply function (`src/events.cr`, `src/apply.cr`)
- [x] Phase 3 — History manager (`src/history.cr`)
- [x] Phase 4 — Extract layout engine (`src/layout.cr`)
- [x] Phase 5 — Model as source of truth + view state separation
- [ ] Phase 6 — Extract renderer (`src/renderer.cr`)
- [ ] Phase 7 — Model-based persistence (replace `*ElementData` mirror structs)
- [ ] Phase 8 — Wire undo/redo (Ctrl+Z/Y)
- [ ] Phase 9 — Fine-grained text events (optional, per-word undo)

**Rule**: The app must compile and run correctly after every phase.  
Phases 1–3 are purely additive (new files only).  
Phases 4–8 progressively cut over existing code.

---

## Design Principles

**Events capture final state, not deltas.** `MoveElementEvent` stores `{new_x, new_y}`, not `{dx, dy}`. Replay is then deterministic regardless of floating-point order or frame timing.

**View-derived values are resolved at emission time.** `max_auto_width` depends on screen size and zoom — capture these into the event when emitted, not when replayed.

**Model has zero Raylib dependency.** Coordinates are plain `Float32`. Colors are `{r,g,b,a : UInt8}`. No `R::Rectangle`, `R::Vector2`, `R::Color` in model files.

**UUIDs are stable across undo/redo.** Elements keep their UUIDs when restored. Arrows reference by UUID so they survive replay correctly.

**Selection and camera are view state, not model state.** They are not part of events or checkpoints.

---

## Key Data Structures

### Model (`src/model.cr`)

```crystal
struct BoundsData
  property x, y, w, h : Float32
end

# ColorData already exists in persistence.cr — consolidate here and reuse
struct ColorData
  property r, g, b, a : UInt8
end

abstract class ElementModel
  property id : UUID
  property bounds : BoundsData
end

class RectModel < ElementModel
  property fill : ColorData
  property stroke : ColorData
  property stroke_width : Float32
  property label : String
end

class TextModel < ElementModel
  property text : String
  property fixed_width : Bool
  property max_auto_width : Float32?
end

class ArrowModel < ElementModel
  property from_id : UUID
  property to_id : UUID
  property routing_style : String  # "orthogonal" | "straight"
  # No circular @elements reference — renderer resolves endpoints from model
end

class CanvasModel
  property elements : Array(ElementModel)

  def find_by_id(id : UUID) : ElementModel?
    @elements.find { |e| e.id == id }
  end
end
```

### Events (`src/events.cr`)

```crystal
abstract struct Event; end

struct CreateRectEvent < Event
  property id : UUID
  property bounds : BoundsData
  property fill : ColorData; property stroke : ColorData; property stroke_width : Float32
  property label : String
end

struct CreateTextEvent < Event
  property id : UUID
  property bounds : BoundsData        # post-fit_content, captured at emission
  property text : String
  property fixed_width : Bool
  property max_auto_width : Float32?  # from R.get_screen_width / zoom — captured at emission
end

struct CreateArrowEvent < Event
  property id : UUID
  property from_id : UUID; property to_id : UUID
  property routing_style : String
end

struct DeleteElementEvent < Event
  property id : UUID
  # Cascaded arrow deletion derived in apply() — not stored in event
end

struct MoveElementEvent < Event
  property id : UUID
  property new_bounds : BoundsData   # final position (not delta)
end

struct MoveMultiEvent < Event
  property moves : Array(Tuple(UUID, BoundsData))
end

struct ResizeElementEvent < Event
  property id : UUID
  property new_bounds : BoundsData
end

struct TextChangedEvent < Event
  property id : UUID
  property new_text : String
  property new_bounds : BoundsData   # post-fit_content
end

struct ArrowRoutingChangedEvent < Event
  property id : UUID
  property new_style : String
end
```

### View State (`src/view_state.cr`)

```crystal
struct ElementViewState
  property cursor_pos : Int32 = 0
  property selection_anchor : Int32? = nil
  property last_input_time : Float64 = 0.0
  property preferred_x : Int32? = nil
end

class CanvasView
  property selected_id : UUID? = nil
  property selected_ids : Array(UUID) = [] of UUID
  property active_tool : ActiveTool = ActiveTool::Selection
  property camera : R::Camera2D
  property drag_mode : DragMode = DragMode::None
  # ... drag temporaries (draw_start, drag_start_mouse, etc.)
  property element_states : Hash(UUID, ElementViewState) = {} of UUID => ElementViewState
end
```

### Layout Cache (`src/layout.cr`)

```crystal
struct TextLayoutData
  property wrapped_lines : Array(String)
  property line_height : Float32
end

struct ArrowLayoutData
  property path_points : Array(R::Vector2)
end

alias ElementLayout = TextLayoutData | ArrowLayoutData | Nil

class LayoutCache
  def get(id : UUID) : ElementLayout
  def invalidate(id : UUID) : Nil
  def compute_if_needed(model : ElementModel) : ElementLayout
    # TextModel → calls TextLayout.compute(text, bounds, font_size)
    # ArrowModel → calls ArrowLayout.compute(from_bounds, to_bounds, style)
    # RectModel → Nil (no layout needed beyond bounds)
  end
end
```

### History Manager (`src/history.cr`)

```crystal
class HistoryManager
  CHECKPOINT_EVERY = 20  # events between automatic checkpoints

  # checkpoints: Array of (serialized CanvasModel JSON, event_log_offset)
  # event_log: flat list of all events since the oldest checkpoint
  # redo_stack: events discarded by undo, available for redo

  def push(event : Event, model : CanvasModel) : Nil
  def undo(current_model : CanvasModel) : CanvasModel?   # nil if nothing to undo
  def redo : {Event, CanvasModel}?                        # nil if nothing to redo

  def can_undo? : Bool
  def can_redo? : Bool

  private def checkpoint(model : CanvasModel) : Nil
  private def replay(snapshot : String, events : Array(Event)) : CanvasModel
end
```

---

## Phase Details

### Phase 0 — Save plan to project
**Goal**: Write this plan as `/workspace/REFACTOR.md`.  
**Files**: Create `/workspace/REFACTOR.md`.  
**Success**: File exists; `shards build` still passes.

---

### Phase 1 — Pure model types
**Goal**: Define model layer with no Raylib dependency.  
**New files**: `src/model.cr`  
**Existing files changed**: None (add `require "./model"` to `canvas.cr` only to verify it compiles).  
**Success**: `shards build` succeeds. Model types exist but are unused. App runs identically.

**Notes**:
- `BoundsData` is a struct (value type for cheap copy in events).
- `ElementModel` is abstract class (reference type, needed for heterogeneous array).
- `ColorData` consolidates the one already in `persistence.cr` — update persistence.cr to use the model's `ColorData` rather than duplicating it.
- `CanvasModel#elements` is `Array(ElementModel)` (preserves draw order). Add `find_by_id` helper for O(n) lookup — fine at this scale.

---

### Phase 2 — Events + apply function
**Goal**: Define all event types and a pure `apply` function.  
**New files**: `src/events.cr`, `src/apply.cr`  
**Existing files changed**: None.  
**Success**: `shards build` succeeds. App runs identically.

**Apply function**:
```crystal
# src/apply.cr
def apply(model : CanvasModel, event : Event) : CanvasModel
  case event
  when CreateRectEvent  then model.elements << RectModel.new(...)
  when DeleteElementEvent
    model.elements.reject! { |e| e.id == event.id }
    # cascade: remove arrows referencing deleted id
    model.elements.reject! do |e|
      e.is_a?(ArrowModel) && (e.from_id == event.id || e.to_id == event.id)
    end
  when MoveElementEvent
    model.find_by_id(event.id).try { |e| e.bounds = event.new_bounds }
  # ... etc.
  end
  model
end
```

**Key rules for apply**:
- `apply` mutates and returns the same model (pragmatic, avoids deep copying the element array).
- `CreateArrowEvent` apply verifies `from_id` and `to_id` exist; no-ops silently if not (guards stale replay).
- `DeleteElementEvent` cascades arrow removal — the event itself only stores the target `id`.

---

### Phase 3 — History manager
**Goal**: Implement checkpoint + event log undo/redo.  
**New files**: `src/history.cr`  
**Existing files changed**: None.  
**Success**: `shards build` succeeds. History class exists but is not wired to any input.

**Checkpoint strategy** (start simple):
- Phase 3 uses a single initial checkpoint (empty model) + full event log.
- Undo replays from checkpoint through `events[0..-2]`.
- Multi-checkpoint optimisation (every 20 events) deferred to Phase 8.

**Undo/redo mechanics**:
```
event_log = [E1, E2, E3, E4, E5]   ← current state
redo_stack = []

Ctrl+Z → save E5 to redo_stack, replay(checkpoint, [E1,E2,E3,E4])
Ctrl+Z → save E4 to redo_stack, replay(checkpoint, [E1,E2,E3])
Ctrl+Y → apply E4 → new state, move E4 back to event_log
New action → push E6 to event_log, clear redo_stack
```

**Model serialisation for checkpoints**: In Phase 3, write a temporary hand-rolled JSON serialiser for `CanvasModel` (parallel to the existing `Canvas#save`). Replace with proper `JSON::Serializable` in Phase 7.

---

### Phase 4 — Extract layout engine
**Goal**: Move word-wrap (TextElement) and arrow routing (ArrowElement) into `src/layout.cr`. Elements call the new module internally — no external interface changes yet.  
**New files**: `src/layout.cr`  
**Existing files changed**: `src/text_element.cr`, `src/arrow_element.cr`  
**Success**: `shards build` succeeds. App renders identically. Layout is now callable externally.

**Text layout**:
- Extract the `wrap_text` private method and `R.measure_text` calls from `text_element.cr` into `TextLayout.compute(text, width, font_size) : TextLayoutData`.
- `TextElement#draw` and `TextElement#contains?` call `TextLayout.compute(...)` instead of their own internals.
- TODO #4 (`fit_content` called every frame) and TODO #19 (`route()` computed multiple times) are partially addressed here by making results cacheable.

**Arrow layout**:
- Extract `route()`, `ortho_route()`, `natural_sides()`, `side_fraction()`, `point_side()` from `arrow_element.cr` into `ArrowLayout.compute(from_bounds, to_bounds, style) : ArrowLayoutData`.
- `ArrowElement#draw` and `ArrowElement#near_line?` call `ArrowLayout.compute(...)`.
- The existing per-instance route cache in `ArrowElement` can be kept for now; `LayoutCache` class replaces it in Phase 6.

**Note**: `TextLayout` calls `R.measure_text` — Raylib dependency is acceptable in the layout layer. Layout bridges model and renderer; it is allowed to use Raylib font metrics.

---

### Phase 5 — Model as source of truth
**Goal**: Canvas maintains `CanvasModel` as primary state. Input handlers emit events applied to model. `@elements` kept as a derived view cache rebuilt after each event. View state (cursor, selection) preserved by UUID.  
**New files**: `src/view_state.cr`  
**Existing files changed**: `src/canvas.cr`, `src/canvas_input.cr`  
**Success**: `shards build` succeeds. App behaves identically. Event log populates (log to stderr in debug builds to verify).

**Canvas changes**:
```crystal
class Canvas
  @model : CanvasModel = CanvasModel.new
  @view  : CanvasView  = CanvasView.new(...)
  @history : HistoryManager = HistoryManager.new

  # @elements and @selected_index kept temporarily as derived cache
  # @camera moves into @view
end
```

**Sync bridge** (temporary, removed in Phase 6):
```crystal
private def sync_elements_from_model
  old_states = capture_view_states   # Hash(UUID, ElementViewState)
  @elements = @model.elements.map { |m| model_to_element(m) }
  @elements.each { |e| e.elements = @elements if e.is_a?(ArrowElement) }
  restore_view_states(old_states)
end
```

**Input handler pattern**:
```crystal
# Before (direct mutation):
@elements[idx].bounds = new_bounds

# After (event emission):
event = MoveElementEvent.new(id: el_id, new_bounds: BoundsData.from_raylib(new_bounds))
@history.push(event, @model)
apply(@model, event)
sync_elements_from_model
```

**Selection**: `@selected_index : Int32?` → `@view.selected_id : UUID?`. Update `select_element`, `hit_test_element` (returns UUID?), `multi_selected?`, `in_multi_selection?`.

**Text session handling**: During active text editing, mutations still apply directly to the element (as today). `TextChangedEvent` is emitted only when the session commits (user clicks away or a non-text action starts). Session commit calls `sync_elements_from_model` + `@history.push`.

**Critical**: `max_auto_width` is set from `R.get_screen_width / (2 * zoom)` in `handle_text_input`. This must be captured into `CreateTextEvent` and `TextChangedEvent` at emission time — not recomputed during replay.

---

### Phase 6 — Extract renderer
**Goal**: Move all `draw` methods out of element classes into `src/renderer.cr`. Elements become data-only; `canvas_drawing.cr` delegates entirely to the renderer.  
**New files**: `src/renderer.cr`  
**Existing files changed**: `src/rect_element.cr`, `src/text_element.cr`, `src/arrow_element.cr`, `src/element.cr`, `src/canvas_drawing.cr`  
**Success**: `shards build` succeeds. App renders identically. Element classes have no `draw` methods.

**Renderer interface**:
```crystal
class Renderer
  def initialize(@layout_cache : LayoutCache); end

  def draw_rect(model : RectModel, vs : ElementViewState?, selected : Bool, camera : R::Camera2D)
  def draw_text(model : TextModel, vs : ElementViewState?, selected : Bool, camera : R::Camera2D)
  def draw_arrow(model : ArrowModel, from_bounds : BoundsData, to_bounds : BoundsData,
                 selected : Bool, camera : R::Camera2D)
  def draw_selection_overlay(model : ElementModel, camera : R::Camera2D)
  def draw_draft(tool : ActiveTool, start : R::Vector2, current : R::Vector2, camera : R::Camera2D)
  def draw_grid(camera : R::Camera2D, viewport : R::Rectangle)
end
```

**Layout cache integration**: `Renderer` owns a `LayoutCache`. Before drawing each element, it calls `@layout_cache.compute_if_needed(model_element)` and uses the result. Cache invalidated when relevant model fields change (version counter per element, or recompute-always for text — it's fast).

**After this phase**: `@elements : Array(Element)` sync bridge from Phase 5 is removed. `canvas.draw` iterates `@model.elements` directly. `draw_hud` receives a `CanvasView` parameter (fixes TODO #12).

**TODOs resolved**: #12, #21.

---

### Phase 7 — Model-based persistence
**Goal**: `CanvasModel` serialises/deserialises directly via `JSON::Serializable`. Remove `*ElementData` mirror structs from `persistence.cr`.  
**Files changed**: `src/persistence.cr`, `src/canvas.cr`, `src/model.cr`  
**Success**: `shards build` succeeds. Save and load work. Existing `canvas.json` files migrated gracefully.

**New serialisation**: Add `include JSON::Serializable` to `BoundsData`, `ColorData`, `RectModel`, `TextModel`, `ArrowModel`, `CanvasModel`. Handle polymorphic deserialisation via `type` field.

**Migration**: On load, detect old format (check for legacy `"rects"` key or old field names). If detected, load via old `*ElementData` path (kept temporarily), construct `CanvasModel`, then save in new format immediately. Remove old loader after two sessions.

**History serialisation**: Phase 3's temporary checkpoint serialiser is replaced with `CanvasModel#to_json` / `CanvasModel.from_json`.

**TODO resolved**: #9.

---

### Phase 8 — Wire undo/redo
**Goal**: Ctrl+Z undoes last event / text session. Ctrl+Y and Ctrl+Shift+Z redo.  
**Files changed**: `src/canvas_input.cr`, `src/canvas.cr`, `src/infinite_canvas.cr`  
**Success**: All mutation types are undoable. Text sessions undo as one step. Redo works. HUD shows hint.

**Key additions**:
- `handle_undo_redo` called first in `Canvas#update`
- `perform_undo` calls `commit_text_session` then `@history.undo`
- `@text_session_id : UUID?` + `@text_session_snapshot` track the active editing session
- Multi-checkpoint optimisation: checkpoint every 20 events, keep at most 5 checkpoints

**TODO resolved**: #28.

---

### Phase 9 — Fine-grained text events (optional)
**Goal**: Per-word undo within a text editing session.  
**Files changed**: `src/events.cr`, `src/apply.cr`, `src/canvas_input.cr`  
**Success**: Ctrl+Z while editing text undoes the last word (or last paste/delete).

**New events**: `InsertTextEvent{id, position, text}`, `DeleteTextEvent{id, start, length, deleted_text}`.

**Coalescing**: Consecutive single-char inserts within a word are merged. Boundaries: whitespace, punctuation, paste/cut/delete, cursor jump > 1 position, pause > 1s.

---

## TODOs from `TODO.md` Addressed by This Refactor

| # | Issue | Phase |
|---|---|---|
| 4 | `fit_content` called every frame | 5 (called only after events) |
| 9 | `to_data` not part of Element interface | 7 (model IS the data) |
| 10 | `handle_left_mouse` too large | 5 (split into emitters) |
| 12 | `draw_hud` knows too much about Canvas | 6 |
| 13 | `ArrowElement#elements` publicly writable | 6 (removed from element) |
| 19 | `route()` computed multiple times per frame | 4 (layout cache) |
| 20 | `side_fraction` is O(N×M) per arrow | 4 (computed once, cached) |
| 21 | `handle_positions` allocates Array every frame | 6 (moved to renderer) |
| 28 | No undo/redo | 8 |

---

## Open Questions (resolve at the start of each phase)

1. **Phase 1**: `CanvasModel#elements` as `Array` (draw order preserved) + `find_by_id` helper. Confirmed.

2. **Phase 2**: `apply` mutates in place (not functional copy). Confirmed pragmatic for Crystal.

3. **Phase 4**: `TextLayout` calls `R.measure_text` — Raylib in layout layer is intentional. Confirmed.

4. **Phase 5**: `@elements` sync bridge is removed in Phase 6. Do not carry it further.

5. **Phase 7**: Old `canvas.json` migration — keep old loader for 2 sessions then delete.
