# Code Review — TODO

## Bugs / edge cases

1. **`@selected_index` is an index, not an identity** — if elements are ever inserted mid-list (z-order reordering, paste-at-position), the selection index silently points to the wrong element. All insertions currently use `@elements << el` so it's safe today, but one refactor away from a subtle bug. Using an object identity reference (`Element?`) would be more robust.

2. **`save` only runs on clean exit** — `canvas.save` is called once at the bottom of the main loop. A crash, force-quit, or SIGTERM loses all unsaved work. Add autosave every N seconds or on every structural change.

3. **Save path is relative to working directory** — `SAVE_FILE = "canvas.json"` resolves relative to wherever the binary is launched from. Running from a different directory silently creates a second file or fails to load the existing one. Use the executable's directory or a platform config dir (e.g. `~/.local/share/`).

4. **`fit_content` called every frame while any element is selected** — in `handle_text_input`, `el.fit_content` is unconditional — it runs every frame even when no key was pressed. For `RectElement` this calls `split('\n')` and `measure_text` per line on every tick. Track a `changed` flag and only call `fit_content` when content actually changed.

5. **`draw_cursor` blink phase is absolute, not reset on keypress** — blink uses `(R.get_time * 2.0).to_i % 2 == 0`. After a keystroke the cursor might immediately vanish if the phase is in the off half-second. Track a `last_input_time` and force-show the cursor for ~0.5 s after any input, as standard editors do.

6. **`TextElement` is completely invisible when empty** — `draw` returns early when `text.empty?`. A freshly-drawn text node disappears the moment it's deselected with nothing typed. Draw a faint placeholder or boundary so the element remains findable.

7. **Draft colour doesn't change with active tool** — dragging with the Text tool still shows the filled blue rectangle draft. The draft should skip the fill (or use a different style) for tools whose elements have no background.

8. **Dangling arrows not cleaned up on load** — `load()` builds the elements array without checking that each arrow's `from_id`/`to_id` refers to an existing element. A save file edited externally, or produced by a future bug, will contain invisible ghost arrows that waste CPU each frame on failed resolve attempts. Add a post-load filter pass to reject arrows whose endpoints are missing.

9. **`natural_sides` validity check uses element centres, but `ortho_route` uses spread coordinates** — `seg2a` in `natural_sides` tests `ey_a > sy` (source centre y), while `ortho_route` with endpoint spreading uses `exit_y` (the ranked position along the side) for the equivalent test. If the spread shifts the exit point past the target edge the two functions disagree: `ortho_route` falls through to a different option than `natural_sides` predicted, so `side_fraction` assigns the arrow to the wrong side group and applies the wrong rank. Rare but a correctness gap near element edges with many arrows.

---

## Architecture / design

10. **`to_data` is not part of the `Element` interface — `save` has a 3-arm `case` switch** — `to_data` is reopened onto each concrete element type in `persistence.cr` but `Element` has no `abstract def to_data` declaration, so `Canvas#save` must enumerate every type. Adding `RectElement`, `TextElement`, and `ArrowElement` each required a new `when` arm. Fix: declare `abstract def to_data : ElementData` on `Element`; then `save` can call `e.to_data.to_json(json)` with no type switch.

11. **`handle_char_input`, `handle_enter`, `handle_backspace` are identical in `RectElement` and `TextElement`** — both do `@<field> += ch.to_s` / `+= "\n"` / `= .rchop`. A shared mixin or `TextualElement < Element` base class would eliminate this duplication and prevent a third copy when a new text-bearing element is added.

12. **`draw_cursor` blink logic is duplicated** — both `RectElement#draw_cursor` and `TextElement#draw_cursor` contain `return unless (R.get_time * 2.0).to_i % 2 == 0`. Extract a protected helper: `def cursor_visible? = (R.get_time * 2.0).to_i.even?`.

13. **`handle_left_mouse` is 70+ lines handling three distinct phases** — split into `handle_mouse_press`, `handle_mouse_drag`, and `handle_mouse_release`. The current method is hard to scan and will only grow as new interaction modes are added.

14. **`draw_hud` in `InfiniteCanvas` is growing toward knowing too much about Canvas internals** — it already reads `active_tool`, `elements.size`, `camera.zoom`, and `selected_element`. Consider a `Canvas#hud_info` method returning a named tuple, keeping rendering in `InfiniteCanvas` but data assembly in `Canvas`.

15. **`ArrowElement#elements` is a public `property`** — the full setter is only needed for the post-load reference patch in `canvas.cr`. Making it publicly writable lets any caller swap the shared array reference, breaking encapsulation. A narrower `def rebind(els : Array(Element))` method or `protected` visibility would tighten the contract.

---

## Maintainability

16. **`label_min_width` and `label_min_height` should be private** — they are implementation details used only by `min_size` and `fit_label`. Making them private prevents callers from bypassing `min_size`.

17. **`RectElement.fit_content` just calls `fit_label` — one should go** — `fit_content` is the polymorphic interface; `fit_label` is the old name. Keeping both adds pointless indirection. Inline `fit_label`'s logic into `fit_content` and remove `fit_label`.

18. **`FONT_SIZE` and `LABEL_FONT_SIZE` are separate constants in two classes, both set to `20`** — changing one leaves the other stale. Extract a shared constant at the top of `element.cr` or in a `Constants` module.

19. **`label.split('\n')` is called repeatedly across methods in the same element** — `draw`, `draw_cursor`, `label_min_width`, `label_min_height`, and `min_size` each call `split('\n')` independently. Cache `@lines : Array(String)` and invalidate it in the `label=`/`text=` setters.

20. **`InfiniteCanvas::VERSION` is declared but never read** — remove it or wire it into the window title.

21. **`property type : String = "rect"` and `@type = "rect"` in data class `initialize` are redundant** — the default value is sufficient; the explicit assignment in `initialize` implies the default alone is not enough. Remove the explicit `@type =` assignments in `RectElementData` and `TextElementData`.

---

## Performance

22. **`route()` is computed 2–3× per frame per arrow** — `draw()` calls `route()`, `near_line?()` calls `route()` (triggered on every mouse move for every arrow), and when selected `draw_highlighted()` calls `route()` a third time. With the full `side_fraction` scan inside each call, this dominates CPU cost as the arrow count grows. Cache the computed waypoint list; invalidate when any element's bounds change.

23. **`side_fraction` is O(N×M) per arrow** (N = arrows sharing the side, M = total elements for ID lookups) — called twice per `ortho_route` invocation. Inside it calls `@elements.find` twice per sibling (O(M) each) and `natural_sides` per sibling. With many arrows this becomes hundreds of element scans per frame. A `HashMap(UUID, Element)` in Canvas, or a cached `{el_id, side} → [arrow_ids]` table rebuilt on structural change, would reduce this to O(1) lookups.

24. **`handle_positions` allocates a new `Array` every frame** — called from `hit_test_handles` and `draw_selection` on every tick. Use a static tuple or yield-based iterator to avoid allocation.

25. **`draw_grid` has no density guard** — at extreme zoom-out (zoom 0.1×) the grid draws thousands of lines. Skip grid lines when `GRID_SPACING * @camera.zoom < 2.0` (they'd be sub-pixel anyway).

26. **`update_bounds_from_points` is called on every `draw()` frame** — the arrow bounding box is recomputed every render even though `ArrowElement#contains?` always returns false and bounds are not used for arrow hit-testing. Skip the update until bounds are actually needed, or track a dirty flag.

27. **`point_side` allocates a 4-element `Array` on every call** — `case [dl, dr, dt, db].min` creates a heap allocation per invocation. Replace with explicit `if/elsif` comparisons to eliminate the allocation; `point_side` is called from `natural_sides` which is called from `side_fraction` which runs in a hot loop.

---

## UX / minor

28. **Arrow line thickness and arrowhead are world-space constants, not screen-space** — `ARROW_WIDTH = 2.0_f32` and `ARROWHEAD_LEN = 14.0_f32` scale with camera zoom like element bounds do. All other zoom-invariant sizes (selection outline `2/zoom`, handles `HANDLE_SIZE/zoom`, grid lines `1/zoom`) use the `pixels / @camera.zoom` pattern. At zoom 0.1× an arrow is barely a hair; at zoom 4× the line is 8 px wide and the arrowhead is 56 px long. Pass zoom into `draw_segments` and apply the same pattern.

29. **`smooth_draw_ms` initialises to 0.0** — the EMA takes ~20 frames (at α = 0.1) to converge, displaying an artificially low draw time on startup. Seed with the first real sample: `smooth_draw_ms = draw_ms` before entering the EMA update.

30. **No `Escape` key to deselect** — clicking on empty space works, but `Escape` is the universal expectation for "cancel / deselect" in canvas apps.

31. **No undo / redo** — any accidental deletion or mistyped label is permanent. The single biggest practical limitation for a note-taking use case.

32. **No multi-select** — `@selected_index : Int32?` allows only one selection. Group-move and group-delete are natural next features.

33. **HUD bottom-right anchors can clip at very small window sizes** — both `R.draw_fps(R.get_screen_width - 100, …)` and the draw-time label `R.get_screen_width - 110 - label_w` go negative or overlap HUD text if the window is resized very small. Guard with `Math.max`.
