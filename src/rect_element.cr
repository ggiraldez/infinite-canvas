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

  def fit_content
    # No-op: LayoutEngine owns sizing. Rect bounds are user-controlled.
  end

end
