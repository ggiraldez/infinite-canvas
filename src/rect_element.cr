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

  def min_size : {Float32, Float32}
    lines  = @label.split('\n')
    max_w  = lines.map { |l| R.measure_text(l, LABEL_FONT_SIZE) }.max? || 0
    total_h = lines.size * LABEL_FONT_SIZE
    {(max_w + LABEL_PADDING_H * 2).to_f32, (total_h + LABEL_PADDING_V * 2).to_f32}
  end

  # Moves the cursor to the label character nearest to *mouse_world* (world space).
  def char_pos_at_world(world_pos : R::Vector2) : Int32
    lines = @label.split('\n')
    return 0 if lines.empty?
    total_h = lines.size * LABEL_FONT_SIZE
    start_y = bounds.y + (bounds.height - total_h) / 2.0_f32
    vi = ((world_pos.y - start_y) / LABEL_FONT_SIZE).to_i.clamp(0, lines.size - 1)
    line = lines[vi]
    line_w = R.measure_text(line, LABEL_FONT_SIZE)
    line_x = bounds.x + (bounds.width - line_w) / 2.0_f32
    rel_x = (world_pos.x - line_x).to_i
    col = nearest_col_for_x(line, rel_x)
    prefix = (0...vi).sum { |i| lines[i].chars.size + 1 }
    (prefix + col).clamp(0, @label.chars.size)
  end

  def place_cursor_at_world_pos(mouse_world : R::Vector2, extend_selection : Bool = false)
    lines = @label.split('\n')
    return if lines.empty?
    total_h = lines.size * LABEL_FONT_SIZE
    start_y = bounds.y + (bounds.height - total_h) / 2.0_f32
    vi = ((mouse_world.y - start_y) / LABEL_FONT_SIZE).to_i.clamp(0, lines.size - 1)
    line = lines[vi]
    line_w = R.measure_text(line, LABEL_FONT_SIZE)
    line_x = bounds.x + (bounds.width - line_w) / 2.0_f32
    rel_x = (mouse_world.x - line_x).to_i
    col = nearest_col_for_x(line, rel_x)
    prefix = (0...vi).sum { |i| lines[i].chars.size + 1 }
    anchor_for_shift(extend_selection)
    @cursor_pos = (prefix + col).clamp(0, @label.chars.size)
    reset_blink
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
end
