# Code Review — TODO

## Bugs / edge cases

1. ~~**`@selected_index` is an index, not an identity**~~ — resolved: `@selected_id : UUID?` and `@selected_ids : Array(UUID)` now track selection by identity; `@selected_index` is a derived cache that is rebuilt after each event via `sync_elements_from_model`.

1a. ~~**`select_element` with an out-of-bounds index set `@selected_index` but cleared `@selected_id`**~~ — resolved: `@selected_index` is now only assigned when `@elements[new_idx]?` succeeds; a missing element clears both fields.

1b. ~~**Forward-delete with an active selection emitted the wrong event**~~ — resolved: `handle_delete` now checks `had_selection` and emits `TextChangedEvent` (full new text) when a selection is deleted, matching the existing backspace behaviour. Previously it always emitted `DeleteTextEvent(length=1)`, de-syncing model from element state for the remainder of the text session.

1c. ~~**`Ctrl+Delete` (forward word-delete) was missing**~~ — resolved: added `handle_forward_delete_word` to `TextEditing` (mirrors `handle_backspace_word` going forward) and wired `Ctrl+Delete` in `handle_delete`.

1d. ~~**Undo/redo during an active drag or draw left `@mode` pointing to stale state**~~ — resolved: `perform_undo` and `perform_redo` now reset `@mode` to `IdleMode` before syncing, so any in-progress drag/resize/draw mode is cleanly cancelled.

1e. ~~**Clicking an arrow (or any non-editable element) without dragging created a spurious undo entry**~~ — resolved: `PressingOnElementMode.on_mouse_release` now compares final bounds against `@drag_start_bounds` and skips `MoveElementEvent` when nothing moved.

1f. ~~**A drag snapped back to origin by the grid still emitted a move/resize event**~~ — resolved: `MovingElementsMode` and `ResizingElementMode` now check whether the element actually moved/changed size before emitting, matching the fix in `PressingOnElementMode`.

1g. ~~**`Enter` key could double-fire on platforms that report it as char code 13**~~ — resolved: the `get_char_pressed` loop now skips code 13; Enter is handled solely by the explicit `key_pressed?` check below.

2. **`save` only runs on clean exit** — `canvas.save` is called once at the bottom of the main loop. A crash, force-quit, or SIGTERM loses all unsaved work. Add autosave every N seconds or on every structural change.

3. **Save path is relative to working directory** — `SAVE_FILE = "canvas.json"` resolves relative to wherever the binary is launched from. Running from a different directory silently creates a second file or fails to load the existing one. Use the executable's directory or a platform config dir (e.g. `~/.local/share/`).

4. ~~**`fit_content` called every frame while any element is selected**~~ — resolved: layout is now computed once per event by `LayoutEngine` and stored in `@render_data`; elements no longer call `fit_content` or `measure_text` each frame.

5. **`TextElement` is completely invisible when empty** — `draw` returns early when `text.empty?`. A freshly-drawn text node disappears the moment it's deselected with nothing typed. Draw a faint placeholder or boundary so the element remains findable.

6. **Draft colour doesn't change with active tool** — dragging with the Text tool still shows the filled blue rectangle draft. The draft should skip the fill (or use a different style) for tools whose elements have no background.

7. **Dangling arrows not cleaned up on load** — `load()` builds the elements array without checking that each arrow's `from_id`/`to_id` refers to an existing element. A save file edited externally, or produced by a future bug, will contain invisible ghost arrows that waste CPU each frame on failed resolve attempts. Add a post-load filter pass to reject arrows whose endpoints are missing.

8. **`natural_sides` validity check uses element centres, but `ortho_route` uses spread coordinates** — `seg2a` in `natural_sides` tests `ey_a > sy` (source centre y), while `ortho_route` with endpoint spreading uses `exit_y` (the ranked position along the side) for the equivalent test. If the spread shifts the exit point past the target edge the two functions disagree: `ortho_route` falls through to a different option than `natural_sides` predicted, so `side_fraction` assigns the arrow to the wrong side group and applies the wrong rank. Rare but a correctness gap near element edges with many arrows.

---

## Architecture / design

9. ~~**`to_data` is not part of the `Element` interface**~~ — resolved: the model layer (`CanvasModel`, `RectModel`, `TextModel`, `ArrowModel`) is the canonical data representation; `Canvas#save` is now `File.write(SAVE_FILE, @model.to_json)`. Mirror structs in `persistence.cr` are retained only as a legacy migration path.

10. ~~**`handle_left_mouse` is 70+ lines handling three distinct phases**~~ — resolved: input is now split across `InputMode` subclasses (`IdleMode`, `PressingOnElementMode`, `MovingElementsMode`, `ResizingElementMode`, `TextEditingMode`, `TextSelectingMode`, `DrawingShapeMode`, `ConnectingArrowMode`, `RubberBandSelectMode`); `handle_left_mouse` dispatches to the active mode.

11. **`draw_hud` in `InfiniteCanvas` is growing toward knowing too much about Canvas internals** — it already reads `active_tool`, `elements.size`, `camera.zoom`, and `selected_element`. Consider a `Canvas#hud_info` method returning a named tuple, keeping rendering in `InfiniteCanvas` but data assembly in `Canvas`.

11a. **Multi-element delete bypasses `emit()`** — `handle_delete` with a multi-selection calls `apply` + `history.push` + `sync_elements_from_model` directly (to batch N deletions into one sync). Future changes to `emit()` will silently not apply here. Extract an `emit_batch(events)` helper that shares the same logic but defers the single sync to the end.

11b. **Duplicated `TextElement`/`RectElement` dispatch in three places** — `idle_mode.cr`, `pressing_on_element_mode.cr` (twice), and `canvas_input.cr` all pattern-match the same two types and call identical methods on each branch. A shared union alias or a `TextEditable` interface would eliminate the repetition.

12. ~~**`ArrowElement#elements` is a public `property`**~~ — resolved: `ArrowElement` no longer holds an `@elements` back-reference; waypoints are injected by the layout pass and stored in `cached_waypoints`.

---

## Maintainability

13. ~~**`label_min_width` and `label_min_height` should be private**~~ — resolved: both methods were removed; label sizing is now handled entirely by `LayoutEngine#layout_rect`.

14. ~~**`RectElement.fit_content` just calls `fit_label` — one should go**~~ — resolved: both `fit_content` and `fit_label` were removed; `LayoutEngine` owns all layout for rect elements.

15. **`FONT_SIZE` and `LABEL_FONT_SIZE` are separate constants in two classes, both set to `20`** — changing one leaves the other stale. Extract a shared constant at the top of `element.cr` or in a `Constants` module.

16. ~~**`label.split('\n')` is called repeatedly across methods in the same element**~~ — resolved: label/text splitting and line measurement are now done once per event inside `LayoutEngine`; the results are cached in `RenderData`.

17. **`InfiniteCanvas::VERSION` is declared but never read** — remove it or wire it into the window title.

18. **`property type : String = "rect"` and `@type = "rect"` in data class `initialize` are redundant** — the default value is sufficient; the explicit assignment in `initialize` implies the default alone is not enough. Remove the explicit `@type =` assignments in `RectElementData` and `TextElementData`.

---

## Performance

19. ~~**`route()` is computed 2–3× per frame per arrow**~~ — resolved: waypoints are computed once per event by `LayoutEngine` and cached in `ArrowRenderData`; `Renderer` and hit-testing read from the cache.

20. ~~**`side_fraction` is O(N×M) per arrow**~~ — resolved: `side_fraction` now runs once per event inside the layout pass rather than on every frame; the per-frame cost is eliminated.

21. **`handle_positions` allocates a new `Array` every frame** — called from `hit_test_handles` and `draw_selection` on every tick. Use a static tuple or yield-based iterator to avoid allocation.

22. **`draw_grid` has no density guard** — at extreme zoom-out (zoom 0.1×) the grid draws thousands of lines. Skip grid lines when `GRID_SPACING * @camera.zoom < 2.0` (they'd be sub-pixel anyway).

23. ~~**`update_bounds_from_points` is called on every `draw()` frame**~~ — resolved: `ArrowElement` no longer holds bounds; arrow bounding boxes are computed by `LayoutEngine` and stored in `ArrowRenderData`.

24. ~~**`point_side` allocates a 4-element `Array` on every call**~~ — resolved: `point_side` is now part of the layout pass (called once per event) rather than a per-frame hot path; the allocation concern no longer applies.

---

## UX / minor

25. **Arrow line thickness and arrowhead are world-space constants, not screen-space** — `ARROW_WIDTH = 2.0_f32` and `ARROWHEAD_LEN = 14.0_f32` scale with camera zoom like element bounds do. All other zoom-invariant sizes (selection outline `2/zoom`, handles `HANDLE_SIZE/zoom`, grid lines `1/zoom`) use the `pixels / @camera.zoom` pattern. At zoom 0.1× an arrow is barely a hair; at zoom 4× the line is 8 px wide and the arrowhead is 56 px long. Pass zoom into `draw_segments` and apply the same pattern.

26. **`smooth_draw_ms` initialises to 0.0** — the EMA takes ~20 frames (at α = 0.1) to converge, displaying an artificially low draw time on startup. Seed with the first real sample: `smooth_draw_ms = draw_ms` before entering the EMA update.

27. ~~**No `Escape` key to deselect**~~ — fixed: `Escape` deselects/cancels; `Ctrl+Q` quits.

28. ~~**No undo / redo**~~ — resolved: full checkpoint-based undo/redo (`Ctrl+Z` / `Ctrl+Y` / `Ctrl+Shift+Z`). Structural events (create, delete, move, resize, arrow style) and text sessions each undo as one step. Per-word undo is active during text editing: consecutive characters coalesce into word groups, with boundaries at whitespace transitions, 1-second pauses, cursor movements, and paste/cut/delete operations.

29. ~~**No multi-select**~~ — resolved: rubber-band drag selects multiple elements; group-move and group-delete are supported.

30. **HUD bottom-right anchors can clip at very small window sizes** — both `R.draw_fps(R.get_screen_width - 100, …)` and the draw-time label `R.get_screen_width - 110 - label_w` go negative or overlap HUD text if the window is resized very small. Guard with `Math.max`.
