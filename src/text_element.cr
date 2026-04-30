require "./text_layout"
require "./font"

# ─── Text node ────────────────────────────────────────────────────────────────

# A plain text node. Holds editing view state (cursor, selection, blink) and
# the text/fixed_width model mirror used during live text sessions.
# All layout is owned by LayoutEngine; cached_line_runs / cached_wraps are
# injected by Canvas after each layout pass.
class TextElement < Element
  include TextEditing

  FONT_SIZE       = 20
  TEXT_COLOR      = R::Color.new(r: 30, g: 30, b: 30, a: 255)
  SELECTION_COLOR = R::Color.new(r: 66, g: 135, b: 245, a: 100)
  PADDING         = 8 # padding on each side in world units

  property text : String
  property fixed_width : Bool
  property cached_line_runs : TextLayoutData? = nil
  property cached_wraps : Bool = false

  def editing_text : String
    @text
  end

  def editing_text=(v : String)
    @text = v
  end

  def editing_font_size : Int32
    FONT_SIZE
  end

  getter font : Font

  def initialize(@font : Font, bounds : R::Rectangle, @text : String = "", id : UUID = UUID.random, @fixed_width : Bool = false)
    super(bounds, id)
    init_cursor
  end

  def resizable? : Bool
    true
  end

  def resizable_width_only? : Bool
    true
  end

  def handle_cursor_up(shift : Bool = false)
    return super unless @fixed_width || @cached_wraps
    anchor_for_shift(shift)
    runs = @cached_line_runs.not_nil!
    vi, x_px = cursor_visual_pos
    return if vi == 0
    target_x = @preferred_x || x_px
    @preferred_x = target_x
    prev_str, prev_start = runs[vi - 1]
    @cursor_pos = prev_start + nearest_col_for_x(prev_str, target_x)
    reset_blink
  end

  def handle_cursor_down(shift : Bool = false)
    return super unless @fixed_width || @cached_wraps
    anchor_for_shift(shift)
    runs = @cached_line_runs.not_nil!
    vi, x_px = cursor_visual_pos
    return if vi >= runs.size - 1
    target_x = @preferred_x || x_px
    @preferred_x = target_x
    next_str, next_start = runs[vi + 1]
    @cursor_pos = next_start + nearest_col_for_x(next_str, target_x)
    reset_blink
  end

  # Moves the cursor to the character nearest to *mouse_world* (world space).
  # Uses cached_line_runs so the visual-line layout matches the renderer exactly.
  def char_pos_at_world(world_pos : R::Vector2) : Int32
    runs = @cached_line_runs
    return 0 unless runs && !runs.empty?
    rel_y = world_pos.y - bounds.y - PADDING
    vi = (rel_y / FONT_SIZE).to_i.clamp(0, runs.size - 1)
    line_str, line_start = runs[vi]
    rel_x = (world_pos.x - bounds.x - PADDING).to_i
    line_start + nearest_col_for_x(line_str, rel_x)
  end

  def place_cursor_at_world_pos(mouse_world : R::Vector2, extend_selection : Bool = false)
    runs = @cached_line_runs
    return if runs.nil? || runs.empty?
    rel_y = mouse_world.y - bounds.y - PADDING
    vi = (rel_y / FONT_SIZE).to_i.clamp(0, runs.size - 1)
    line_str, line_start = runs[vi]
    rel_x = (mouse_world.x - bounds.x - PADDING).to_i
    anchor_for_shift(extend_selection)
    @cursor_pos = line_start + nearest_col_for_x(line_str, rel_x)
    reset_blink
  end

  # Maps @cursor_pos to {visual_line_index, x_pixel_offset_within_line}.
  # Private: used only for cursor-up/down navigation and by Renderer (which
  # has its own copy to avoid a public Raylib dependency on this class).
  private def cursor_visual_pos : {Int32, Int32}
    runs = @cached_line_runs.not_nil!
    return {0, 0} if runs.empty?
    runs.each_with_index do |(line_str, line_start), vi|
      next_start = vi + 1 < runs.size ? runs[vi + 1][1] : Int32::MAX
      if @cursor_pos >= line_start && @cursor_pos < next_start
        col = [@cursor_pos - line_start, line_str.chars.size].min
        x_px = @font.measure(line_str.chars[0...col].join)
        return {vi, x_px}
      end
    end
    last_line = runs.last[0]
    {runs.size - 1, @font.measure(last_line)}
  end
end
