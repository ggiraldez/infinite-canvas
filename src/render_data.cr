require "./model"
require "./text_layout"

# text → pixel_width.  Injected into LayoutEngine so layout has no hard
# Raylib dependency and can be unit-tested with a stub.
alias Measurer = Proc(String, Int32)

struct TextRenderData
  property bounds : BoundsData
  property line_runs : TextLayoutData
  property wraps : Bool

  def initialize(@bounds : BoundsData, @line_runs : TextLayoutData, @wraps : Bool)
  end
end

struct RectRenderData
  property bounds : BoundsData
  property label_lines : Array({String, Int32}) # (line_text, pixel_width) per line

  def initialize(@bounds : BoundsData, @label_lines : Array({String, Int32}))
  end
end

struct ArrowRenderData
  property waypoints : Array({Float32, Float32})
  property bounds : BoundsData

  def initialize(@waypoints : Array({Float32, Float32}), @bounds : BoundsData)
  end
end

alias ElementRenderData = TextRenderData | RectRenderData | ArrowRenderData
alias RenderData = Hash(UUID, ElementRenderData)
