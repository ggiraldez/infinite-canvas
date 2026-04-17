# ─── Text node ────────────────────────────────────────────────────────────────

# A plain text node: no background rectangle, text top-left aligned within bounds.
class TextElement < Element
  include TextEditing

  FONT_SIZE       = 20
  TEXT_COLOR      = R::Color.new(r: 30, g: 30, b: 30, a: 255)
  SELECTION_COLOR = R::Color.new(r: 66, g: 135, b: 245, a: 100)
  PADDING         =  8  # padding on each side in world units

  property text : String

  def editing_text : String
    @text
  end

  def editing_text=(v : String)
    @text = v
  end

  def editing_font_size : Int32
    FONT_SIZE
  end

  def initialize(bounds : R::Rectangle, @text : String = "", id : UUID = UUID.random)
    super(bounds, id)
    init_cursor
  end

  def resizable? : Bool
    false
  end

  def draw
    return if text.empty?
    lines = text.split('\n')
    lines.each_with_index do |line, i|
      R.draw_text(line,
        bounds.x.to_i + PADDING,
        (bounds.y + PADDING + i * FONT_SIZE).to_i,
        FONT_SIZE, TEXT_COLOR)
    end
  end

  def min_size : {Float32, Float32}
    if text.empty?
      # Reserve enough space for the blinking cursor with padding on all sides,
      # so a freshly-created text node looks intentional rather than invisible.
      cursor_w = R.measure_text("|", FONT_SIZE)
      return {(cursor_w + PADDING * 2).to_f32, (FONT_SIZE + PADDING * 2).to_f32}
    end
    lines = text.split('\n')
    max_tw = lines.map { |l| R.measure_text(l, FONT_SIZE) }.max? || 0
    {(max_tw + PADDING * 2).to_f32, (lines.size * FONT_SIZE + PADDING * 2).to_f32}
  end

  def fit_content
    mw, mh = min_size
    # Text nodes are always sized to exactly fit their content — never larger.
    @bounds = R::Rectangle.new(x: bounds.x, y: bounds.y, width: mw, height: mh)
  end

  def draw_cursor
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
end
