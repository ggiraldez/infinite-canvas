require "../src/font_metrics"

# Test stub: fixed-width characters with configurable spacing.
# measure(text) = text.size * char_width + (text.size - 1) * spacing_px
# matching how a real proportional renderer accumulates glyph widths + inter-glyph gaps.
class StubFontMetrics < FontMetrics
  def initialize(@char_width : Int32 = 10, @size : Int32 = 20, @spacing_px : Int32 = 0)
  end

  def measure(text : String) : Int32
    text.size * @char_width + [text.size - 1, 0].max * @spacing_px
  end

  getter size : Int32

  def spacing : Float32
    @spacing_px.to_f32
  end
end
