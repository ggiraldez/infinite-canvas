# View state for an individual editable element.
# Captures cursor/selection state that lives on element objects today.
# Phase 5: defined here for forward compatibility; not yet used because
#   text editing and sync_elements_from_model do not interleave.
# Phase 6: the renderer will read ElementViewState instead of calling
#   element methods, removing the last Raylib coupling from element classes.
struct ElementViewState
  property cursor_pos : Int32 = 0
  property selection_anchor : Int32? = nil
  property last_input_time : Float64 = 0.0
  property preferred_x : Int32? = nil
end
