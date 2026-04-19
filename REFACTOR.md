# Refactor: Intermediate Layout Pass

## Context

All layout work currently happens inside Renderer and Element methods on every frame:
- `ArrowElement#compute_path` runs full orthogonal routing (including an O(n²) `side_fraction` scan over all arrows) every frame per arrow, and again during hit-testing via `near_line?`.
- `TextElement#visual_line_runs` calls `TextLayout.compute` — O(n) `R.measure_text` calls per wrapped text element — every frame.
- `Renderer#draw_rect_label` and cursor/selection methods call `R.measure_text` per line per frame.

The goal is a single layout pass that runs once after each event, producing complete render-ready data. The Renderer then just draws — no computation. Layout must not have a hard Raylib dependency (the measurer is injected), so it can be unit-tested.

The existing `view_state.cr` (`ElementViewState`) and the `# Phase 5 / Phase 6` comments in that file already anticipate this direction.

---

## Phase 1 — Measurer type + LayoutEngine skeleton

**Goal:** Establish the contracts. Run a layout pass after every event but leave the Renderer unchanged. Proves the approach without breaking anything.

### New file: `src/render_data.cr` (no Raylib dependency)
```crystal
alias Measurer = Proc(String, Int32, Int32)   # (text, font_size) → pixel_width

struct TextRenderData
  property bounds    : BoundsData
  property line_runs : TextLayoutData   # from text_layout.cr
  property wraps     : Bool
end

struct RectRenderData
  property bounds      : BoundsData
  property label_lines : Array({String, Int32})  # (line_text, pixel_width) per line
end

struct ArrowRenderData
  property waypoints : Array({Float32, Float32})  # pairs, not R::Vector2
  property bounds    : BoundsData
end

alias ElementRenderData = TextRenderData | RectRenderData | ArrowRenderData
alias RenderData = Hash(UUID, ElementRenderData)
```

### New file: `src/layout_engine.cr`
```crystal
class LayoutEngine
  def initialize(@measure : Measurer); end
  def layout(model : CanvasModel) : RenderData
    # Iterates model.elements, dispatches to private layout_text / layout_rect / layout_arrow
    # Initially wraps existing logic: fit_content for text, label sizing for rect,
    # straight_route / ortho_route stub for arrows.
    # Returns a RenderData hash keyed by element UUID.
  end
end
```

### Wire into `canvas.cr`
- Add `@layout_engine : LayoutEngine` (constructed with `R.measure_text` proc).
- Add `@render_data : RenderData`.
- After every `emit` and `emit_text_event`, call `@render_data = @layout_engine.layout(@model)`.
- Renderer still reads element methods — no visible change to output.

### Tests
- Unit-test `LayoutEngine#layout` with a stub measurer (same `s.size * 10` approach used in `text_layout_spec.cr`).
- Verify correct `TextRenderData` (bounds, line_runs) and `RectRenderData` (label_lines) for simple models.

**Modified files:** `canvas.cr`, new `src/render_data.cr`, new `src/layout_engine.cr`

---

## Phase 2 — Arrow layout in LayoutEngine

**Goal:** Eliminate `compute_path` / `side_fraction` / `ortho_route` from `ArrowElement`, and the `@elements` back-reference. Arrow layout runs once per event.

### In `layout_engine.cr`
- Implement `layout_arrow(model, arrow_model)` using `CanvasModel` for all sibling lookups — no `Array(Element)` needed.
- Port `side_fraction` logic here, operating on `Array(ArrowModel)` from the model.
- Call `ArrowLayout.straight_route` / `ArrowLayout.natural_sides` / `ArrowLayout.exit_point_on_side` (they stay in `arrow_layout.cr`; only the high-level routing moves).
- Move `ortho_route` from `ArrowElement` into `arrow_layout.cr` as a module-level method taking explicit bounds + fraction arguments (now possible because LayoutEngine supplies everything).

### In `ArrowElement`
- Remove `@elements : Array(Element)` property.
- Remove `private def ortho_route`, `private def side_fraction`.
- Remove `property elements` setter (used in `sync_elements_from_model`).
- `compute_path` becomes a thin wrapper that reads `@cached_waypoints : Array(R::Vector2)?` (set from canvas after layout pass). Returns nil if not yet set.
- `near_line?` uses `@cached_waypoints`.

### In `canvas.cr` / `sync_elements_from_model`
- After layout pass, iterate arrows and inject pre-computed waypoints as `R::Vector2` pairs (convert from `{Float32, Float32}`).
- Remove `@elements.each { |e| e.elements = @elements if e.is_a?(ArrowElement) }` patch.

### Tests
- Unit-test `LayoutEngine` arrow routing with a simple two-element model.
- Verify spread fractions with multiple arrows on the same side.

**Modified files:** `arrow_element.cr`, `arrow_layout.cr`, `layout_engine.cr`, `canvas.cr`

---

## Phase 3 — Text and Rect layout in LayoutEngine

**Goal:** Eliminate per-frame `R.measure_text` calls from `TextElement` and `RectElement`. `visual_line_runs` becomes a cached read.

### In `layout_engine.cr`
- `layout_text(model, text_model)`: compute `TextLayout.compute` (already takes measurer block), derive bounds (fit_content logic), set `wraps`.
- `layout_rect(model, rect_model)`: measure each label line, compute `label_lines : Array({String, Int32})`.
- Bounds written back into the LayoutEngine output only — model bounds updated via events, not here.

### In `TextElement`
- Add `@cached_line_runs : TextLayoutData?` property.
- `visual_line_runs` returns `@cached_line_runs.not_nil!` (panics if layout hasn't run — acceptable: layout always precedes draw).
- `fit_content` removed or reduced to a no-op (LayoutEngine owns fit logic now).
- `cursor_visual_pos` and `visual_selection_ranges` still operate on `@cached_line_runs` — no change to their signatures.

### In `RectElement`
- `label_min_width` / `label_min_height` removed (LayoutEngine computes this).
- `fit_content` / `fit_label` removed.

### In `canvas.cr` / `sync_elements_from_model`
- After layout pass, inject `line_runs` into each `TextElement` via `el.cached_line_runs = ...`.
- Remove `el.fit_content` call from the sync.

### Tests
- Extend `LayoutEngine` tests to cover text wrapping, multi-paragraph, and rect label line widths.

**Modified files:** `text_element.cr`, `rect_element.cr`, `layout_engine.cr`, `canvas.cr`

---

## Phase 4 — Renderer reads from RenderData

**Goal:** Renderer receives `RenderData` alongside elements and reads pre-computed data. All `R.measure_text` calls removed from `Renderer`.

### Renderer API changes
- `draw_element(el, rd : ElementRenderData)` — renderer takes the pre-computed data.
- `draw_rect(el, rd : RectRenderData)`: use `rd.label_lines` for centering; no `R.measure_text`.
- `draw_text(el, rd : TextRenderData)`: use `rd.line_runs` for wrapped draw; no `el.visual_line_runs` call.
- `draw_arrow(el, rd : ArrowRenderData)`: use `rd.waypoints` converted to `R::Vector2`; no `el.compute_path`.
- Cursor/selection drawing (`draw_cursor`): still reads element for `cursor_pos` / `selection_range` (view state), but uses `rd.line_runs` / `rd.label_lines` for pixel offsets instead of calling `R.measure_text`.

### In `canvas.cr`
- `draw_element` loop passes matching `@render_data[el.id]` to Renderer.
- Arrow bounds (for culling decisions) read from `@render_data` rather than `el.bounds`.

### Tests
- Renderer is inherently coupled to Raylib; these changes are verified by running the app and checking visual correctness.

**Modified files:** `renderer.cr`, `canvas.cr`

---

## Phase 5 — Element class cleanup

**Goal:** Element subclasses hold only view state (cursor, selection, blink timestamp). All layout concerns removed.

### Remove from `TextElement`
- `visual_line_runs`, `cursor_visual_pos`, `visual_selection_ranges` (Renderer uses RenderData).
- `fit_content`, `@auto_capped`, `@max_auto_width` (LayoutEngine owns this now, reads from model).
- `wraps?` — derived from `TextRenderData.wraps` by Renderer.
- `min_size` — removed (LayoutEngine computes bounds; Canvas uses RenderData for resize clamping).

### Remove from `ArrowElement`
- `compute_path`, `near_line?` skeleton wrappers (Renderer reads from RenderData; hit-testing uses cached waypoints from RenderData directly in Canvas).
- `update_bounds_from_points`.
- `segment_dist` moves to a standalone helper or stays as a free function.

### Remove from `RectElement`
- `label_min_width`, `label_min_height`, `fit_content`, `fit_label`.

### Align with `ElementViewState`
- At this point the surviving element state (cursor_pos, selection_anchor, last_input_time, preferred_x) matches the existing `ElementViewState` struct in `view_state.cr`.
- Consider merging: Canvas holds `@view_states : Hash(UUID, ElementViewState)` instead of `@elements : Array(Element)` — or keep thin Element wrappers for the TextEditing mixin behaviour.

### Tests
- All existing unit tests (model, apply, history, text_editing, text_layout, layout_engine) should still pass.
- Build with `LIBRARY_PATH=$PWD/local/lib shards build` and smoke-test the running app.

**Modified files:** `text_element.cr`, `rect_element.cr`, `arrow_element.cr`, `element.cr`, `canvas.cr`, `view_state.cr`

---

## Critical files

| File | Role |
|------|------|
| `src/render_data.cr` | NEW — Raylib-free render data types + Measurer alias |
| `src/layout_engine.cr` | NEW — computes RenderData from CanvasModel + Measurer |
| `src/canvas.cr` | Wire layout pass into emit / emit_text_event / sync |
| `src/renderer.cr` | Consume RenderData instead of calling element methods |
| `src/text_element.cr` | Remove layout methods, expose cached_line_runs |
| `src/rect_element.cr` | Remove fit_content / label measuring |
| `src/arrow_element.cr` | Remove routing, remove @elements back-ref |
| `src/arrow_layout.cr` | Receive ortho_route from ArrowElement |
| `src/text_layout.cr` | Already has measurer block — no change needed |
| `src/view_state.cr` | Phase 5 destination for surviving element view state |

## Verification per phase

- **Phase 1:** `crystal spec spec/` all green; app builds and behaves identically.
- **Phase 2:** Arrow routing visually correct; spec covers side_fraction spread logic.
- **Phase 3:** Wrapped text displays correctly; spec covers fit_content bounds for text and rect labels.
- **Phase 4:** No `R.measure_text` in `renderer.cr`; visual output identical; no performance regression.
- **Phase 5:** All specs green; `grep -r "visual_line_runs\|compute_path\|fit_content\|label_min_width" src/` returns nothing in element files.
