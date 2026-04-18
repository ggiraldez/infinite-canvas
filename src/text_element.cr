require "./layout"

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
  # Set by Canvas each time fit_content is called; limits auto-grow width.
  property max_auto_width : Float32? = nil
  # True when auto-width is soft-capped (not user-set, but content exceeds cap).
  @auto_capped : Bool = false

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

  # True when the text should be rendered with word-wrap:
  # either the user explicitly set a width, or auto-width hit the cap.
  def wraps? : Bool
    @fixed_width || @auto_capped
  end

  def draw
    return if text.empty?
    if wraps?
      visual_line_runs.each_with_index do |(line, _), i|
        R.draw_text(line,
          bounds.x.to_i + PADDING,
          (bounds.y + PADDING + i * FONT_SIZE).to_i,
          FONT_SIZE, TEXT_COLOR)
      end
    else
      text.split('\n').each_with_index do |line, i|
        R.draw_text(line,
          bounds.x.to_i + PADDING,
          (bounds.y + PADDING + i * FONT_SIZE).to_i,
          FONT_SIZE, TEXT_COLOR)
      end
    end
  end

  def min_size : {Float32, Float32}
    # Minimum allowed width for resize clamping — narrow enough to allow free dragging.
    min_w = (PADDING * 2 + R.measure_text("W", FONT_SIZE)).to_f32
    if text.empty?
      return {min_w, (FONT_SIZE + PADDING * 2).to_f32}
    end
    if wraps?
      line_count = visual_line_runs.size
      {min_w, (line_count * FONT_SIZE + PADDING * 2).to_f32}
    else
      lines = text.split('\n')
      max_tw = lines.map { |l| R.measure_text(l, FONT_SIZE) }.max? || 0
      {(max_tw + PADDING * 2).to_f32, (lines.size * FONT_SIZE + PADDING * 2).to_f32}
    end
  end

  def fit_content
    if @fixed_width
      # User locked the width — preserve it, recompute height from wrapped content.
      @auto_capped = false
      line_count = text.empty? ? 1 : visual_line_runs.size
      mh = (line_count * FONT_SIZE + PADDING * 2).to_f32
      @bounds = R::Rectangle.new(x: bounds.x, y: bounds.y, width: bounds.width, height: mh)
      return
    end

    # Auto mode: measure uncapped content size.
    if text.empty?
      cursor_w = R.measure_text("|", FONT_SIZE)
      content_w = (cursor_w + PADDING * 2).to_f32
      content_h = (FONT_SIZE + PADDING * 2).to_f32
    else
      lines = text.split('\n')
      max_tw = lines.map { |l| R.measure_text(l, FONT_SIZE) }.max? || 0
      content_w = (max_tw + PADDING * 2).to_f32
      content_h = (lines.size * FONT_SIZE + PADDING * 2).to_f32
    end

    cap = @max_auto_width
    if cap && content_w > cap
      # Soft-cap: clamp width and wrap text for the height calculation.
      @auto_capped = true
      @bounds = R::Rectangle.new(x: bounds.x, y: bounds.y, width: cap, height: bounds.height)
      line_count = text.empty? ? 1 : visual_line_runs.size
      mh = (line_count * FONT_SIZE + PADDING * 2).to_f32
      @bounds = R::Rectangle.new(x: bounds.x, y: bounds.y, width: cap, height: mh)
    else
      @auto_capped = false
      @bounds = R::Rectangle.new(x: bounds.x, y: bounds.y, width: content_w, height: content_h)
    end
  end

  def draw_cursor
    if wraps?
      draw_cursor_wrapped
    else
      draw_cursor_raw
    end
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

  # ─── private ──────────────────────────────────────────────────────────────────

  # Returns visual lines as {line_text, start_offset_in_full_text} pairs.
  # Delegates to TextLayout.compute — algorithm and documentation live there.
  private def visual_line_runs : TextLayoutData
    TextLayout.compute(@text, (bounds.width - PADDING * 2).to_f32, FONT_SIZE)
  end

  # Maps @cursor_pos (character offset in full text) to
  # {visual_line_index, x_pixel_offset_within_line}.
  private def cursor_visual_pos : {Int32, Int32}
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
  private def visual_selection_ranges(sel_start : Int32, sel_end : Int32) : Array({Int32, Int32, Int32})
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

  private def draw_cursor_raw
    if (range = selection_range)
      all_lines = text.split('\n')
      selection_line_ranges(range[0], range[1]).each do |line_idx, col_start, col_end|
        line  = all_lines.fetch(line_idx, "")
        chars = line.chars
        x1 = bounds.x + PADDING + R.measure_text(chars[0, col_start].join, FONT_SIZE)
        x2 = bounds.x + PADDING + R.measure_text(chars[0, col_end].join, FONT_SIZE)
        y  = bounds.y + PADDING + line_idx * FONT_SIZE
        R.draw_rectangle_rec(R::Rectangle.new(x: x1, y: y, width: x2 - x1, height: FONT_SIZE.to_f32), SELECTION_COLOR)
      end
    end

    return unless cursor_visible?
    lines_b  = lines_before_cursor
    line_idx = lines_b.size - 1
    col_text = lines_b.last
    tw = R.measure_text(col_text, FONT_SIZE)
    cx = bounds.x.to_i + PADDING + tw
    cy = (bounds.y + PADDING + line_idx * FONT_SIZE).to_i
    R.draw_text("|", cx, cy, FONT_SIZE, TEXT_COLOR)
  end

  private def draw_cursor_wrapped
    if (range = selection_range)
      all_runs = visual_line_runs
      visual_selection_ranges(range[0], range[1]).each do |vi, col_start, col_end|
        line_str = all_runs.fetch(vi, {"", 0})[0]
        chars    = line_str.chars
        x1 = bounds.x + PADDING + R.measure_text(chars[0, col_start].join, FONT_SIZE)
        x2 = bounds.x + PADDING + R.measure_text(chars[0, col_end].join, FONT_SIZE)
        y  = bounds.y + PADDING + vi * FONT_SIZE
        R.draw_rectangle_rec(R::Rectangle.new(x: x1, y: y, width: x2 - x1, height: FONT_SIZE.to_f32), SELECTION_COLOR)
      end
    end

    return unless cursor_visible?
    vi, x_px = cursor_visual_pos
    cx = (bounds.x + PADDING + x_px).to_i
    cy = (bounds.y + PADDING + vi * FONT_SIZE).to_i
    R.draw_text("|", cx, cy, FONT_SIZE, TEXT_COLOR)
  end
end
