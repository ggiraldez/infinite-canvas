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

  def min_size : {Float32, Float32}
    {label_min_width, label_min_height}
  end

  def fit_content
    fit_label
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

end
