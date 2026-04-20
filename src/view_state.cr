# View state for an individual editable element.
# Matches the surviving state in TextElement / RectElement after Phase 5 cleanup:
# cursor position, selection anchor, last input timestamp, and preferred x column.
struct ElementViewState
  property cursor_pos : Int32 = 0
  property selection_anchor : Int32? = nil
  property last_input_time : Float64 = 0.0
  property preferred_x : Int32? = nil
end
