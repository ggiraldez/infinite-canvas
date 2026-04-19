require "./text_layout"

# ─── Text node ────────────────────────────────────────────────────────────────

# A plain text node: no background rectangle, text top-left aligned within bounds.
class TextElement < Element
  include TextEditing

  FONT_SIZE       = 20
  TEXT_COLOR      = R::Color.new(r: 30, g: 30, b: 30, a: 255)
  SELECTION_COLOR = R::Color.new(r: 66, g: 135, b: 245, a: 100)
  PADDING         =  8  # padding on each side in world units

  property text : String
  property fixed_width : Bool
  property max_auto_width : Float32? = nil
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

  def initialize(bounds : R::Rectangle, @text : String = "", id : UUID = UUID.random, @fixed_width : Bool = false)
    super(bounds, id)
    init_cursor
  end

  def resizable? : Bool
    true
  end

  def resizable_width_only? : Bool
    true
  end

  # True when the text should be rendered with word-wrap.
  def wraps? : Bool
    @fixed_width || @cached_wraps
  end

  def min_size : {Float32, Float32}
    line_count = @cached_line_runs.try(&.size) || 1
    {(PADDING * 2 + 10).to_f32, (line_count * FONT_SIZE + PADDING * 2).to_f32}
  end

  def fit_content
    # No-op: LayoutEngine owns all sizing. Canvas calls refresh_element_layout
    # after text changes, which injects cached_line_runs and updates bounds.
  end

  def handle_cursor_up(shift : Bool = false)
    return super unless wraps?
    anchor_for_shift(shift)
    runs = visual_line_runs
    vi, x_px = cursor_visual_pos
    return if vi == 0
    target_x = @preferred_x || x_px
    @preferred_x = target_x
    prev_str, prev_start = runs[vi - 1]
    @cursor_pos = prev_start + nearest_col_for_x(prev_str, target_x)
    reset_blink
  end

  def handle_cursor_down(shift : Bool = false)
    return super unless wraps?
    anchor_for_shift(shift)
    runs = visual_line_runs
    vi, x_px = cursor_visual_pos
    return if vi >= runs.size - 1
    target_x = @preferred_x || x_px
    @preferred_x = target_x
    next_str, next_start = runs[vi + 1]
    @cursor_pos = next_start + nearest_col_for_x(next_str, target_x)
    reset_blink
  end

  # Returns cached visual line runs. Panics if layout hasn't run yet —
  # layout always precedes draw and cursor navigation.
  def visual_line_runs : TextLayoutData
    @cached_line_runs.not_nil!
  end

  # Maps @cursor_pos (character offset in full text) to
  # {visual_line_index, x_pixel_offset_within_line}.
  def cursor_visual_pos : {Int32, Int32}
    runs = visual_line_runs
    return {0, 0} if runs.empty?

    runs.each_with_index do |(line_str, line_start), vi|
      next_start = vi + 1 < runs.size ? runs[vi + 1][1] : Int32::MAX
      if @cursor_pos >= line_start && @cursor_pos < next_start
        # Clamp to the end of the line in case cursor is on a swallowed space.
        col = [@cursor_pos - line_start, line_str.chars.size].min
        x_px = R.measure_text(line_str.chars[0...col].join, FONT_SIZE)
        return {vi, x_px}
      end
    end

    # Fallback: cursor at end of last line.
    last_line = runs.last[0]
    {runs.size - 1, R.measure_text(last_line, FONT_SIZE)}
  end

  # Returns {visual_line_idx, col_start, col_end} for each visual line that
  # overlaps the character range [sel_start, sel_end).
  def visual_selection_ranges(sel_start : Int32, sel_end : Int32) : Array({Int32, Int32, Int32})
    result = [] of {Int32, Int32, Int32}
    visual_line_runs.each_with_index do |(line_str, line_start), vi|
      line_chars = line_str.chars.size
      line_end   = line_start + line_chars
      if sel_start <= line_end && sel_end > line_start
        col_start = [sel_start - line_start, 0].max
        col_end   = [sel_end   - line_start, line_chars].min
        result << {vi, col_start, col_end}
      end
    end
    result
  end
end
