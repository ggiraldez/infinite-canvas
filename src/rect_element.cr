# ─── Rectangle ────────────────────────────────────────────────────────────────

class RectElement < Element
  include TextEditing

  LABEL_FONT_SIZE  = 20
  LABEL_COLOR      = R::Color.new(r: 255, g: 255, b: 255, a: 230)
  SELECTION_COLOR  = R::Color.new(r: 255, g: 255, b: 255, a: 70)
  LABEL_PADDING_H  = 16  # minimum horizontal padding on each side
  LABEL_PADDING_V  = 12  # minimum vertical padding on each side

  property fill : R::Color
  property stroke : R::Color
  property stroke_width : Float32
  property label : String

  def editing_text : String
    @label
  end

  def editing_text=(v : String)
    @label = v
  end

  def editing_font_size : Int32
    LABEL_FONT_SIZE
  end

  def initialize(bounds : R::Rectangle,
                 @fill : R::Color = R::Color.new(r: 90, g: 140, b: 220, a: 200),
                 @stroke : R::Color = R::Color.new(r: 30, g: 60, b: 120, a: 255),
                 @stroke_width : Float32 = 2.0_f32,
                 @label : String = "",
                 id : UUID = UUID.random)
    super(bounds, id)
    init_cursor
  end

  def draw
    R.draw_rectangle_rec(bounds, fill)
    R.draw_rectangle_lines_ex(bounds, stroke_width, stroke)
    draw_centered_text(label)
  end

  def min_size : {Float32, Float32}
    {label_min_width, label_min_height}
  end

  def fit_content
    fit_label
  end

  def draw_cursor
    all_lines = label.split('\n')
    total_h   = all_lines.size * LABEL_FONT_SIZE

    if (range = selection_range)
      selection_line_ranges(range[0], range[1]).each do |line_idx, col_start, col_end|
        line    = all_lines.fetch(line_idx, "")
        chars   = line.chars
        full_tw = R.measure_text(line, LABEL_FONT_SIZE)
        line_x  = bounds.x + (bounds.width - full_tw) / 2.0_f32
        x1 = line_x + R.measure_text(chars[0, col_start].join, LABEL_FONT_SIZE)
        x2 = line_x + R.measure_text(chars[0, col_end].join, LABEL_FONT_SIZE)
        y  = bounds.y + (bounds.height - total_h) / 2.0_f32 + line_idx * LABEL_FONT_SIZE
        R.draw_rectangle_rec(R::Rectangle.new(x: x1, y: y, width: x2 - x1, height: LABEL_FONT_SIZE.to_f32), SELECTION_COLOR)
      end
    end

    return unless cursor_visible?
    lines_b  = lines_before_cursor
    line_idx = lines_b.size - 1
    col_text = lines_b.last
    cur_line = all_lines.fetch(line_idx, "")
    full_tw  = R.measure_text(cur_line, LABEL_FONT_SIZE)
    col_tw   = R.measure_text(col_text, LABEL_FONT_SIZE)
    # Text on each line is centred; cursor sits at the end of col_text on cur_line.
    cx = (bounds.x + (bounds.width - full_tw) / 2.0_f32 + col_tw).to_i
    cy = (bounds.y + (bounds.height - total_h) / 2.0_f32 + line_idx * LABEL_FONT_SIZE).to_i
    R.draw_text("|", cx, cy, LABEL_FONT_SIZE, LABEL_COLOR)
  end

  # Minimum width needed to display the current label without clipping.
  # Returns 4.0 when the label is empty so the bare minimum size is unchanged.
  def label_min_width : Float32
    return 4.0_f32 if label.empty?
    lines = label.split('\n')
    max_tw = lines.map { |l| R.measure_text(l, LABEL_FONT_SIZE) }.max? || 0
    (max_tw + LABEL_PADDING_H * 2).to_f32
  end

  # Minimum height needed to display the current label without clipping.
  # Returns 4.0 when the label is empty so the bare minimum size is unchanged.
  def label_min_height : Float32
    return 4.0_f32 if label.empty?
    lines = label.split('\n')
    (lines.size * LABEL_FONT_SIZE + LABEL_PADDING_V * 2).to_f32
  end

  # Expands bounds in-place so the label fits, never shrinks.
  def fit_label
    new_w = Math.max(bounds.width, label_min_width)
    new_h = Math.max(bounds.height, label_min_height)
    @bounds = R::Rectangle.new(x: bounds.x, y: bounds.y, width: new_w, height: new_h)
  end

  # Draws *text* horizontally and vertically centred inside bounds.
  # Newline characters split the text into multiple centred lines.
  def draw_centered_text(text : String)
    return if text.empty?
    lines = text.split('\n')
    total_height = lines.size * LABEL_FONT_SIZE
    start_y = bounds.y + (bounds.height - total_height) / 2.0_f32
    lines.each_with_index do |line, i|
      tw = R.measure_text(line, LABEL_FONT_SIZE)
      lx = (bounds.x + (bounds.width - tw) / 2.0_f32).to_i
      ly = (start_y + i * LABEL_FONT_SIZE).to_i
      R.draw_text(line, lx, ly, LABEL_FONT_SIZE, LABEL_COLOR)
    end
  end
end
