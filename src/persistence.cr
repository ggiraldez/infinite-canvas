require "json"
require "uuid"
require "./element"

# JSON-serializable mirror of R::Color.
struct ColorData
  include JSON::Serializable

  property r : UInt8
  property g : UInt8
  property b : UInt8
  property a : UInt8

  def initialize(c : R::Color)
    @r, @g, @b, @a = c.r, c.g, c.b, c.a
  end

  def to_raylib : R::Color
    R::Color.new(r: @r, g: @g, b: @b, a: @a)
  end
end

# ─── Concrete data classes ─────────────────────────────────────────────────────

class RectElementData < ElementData
  include JSON::Serializable

  property type : String = "rect"
  property id : String = UUID.random.to_s
  property x : Float32
  property y : Float32
  property width : Float32
  property height : Float32
  property fill : ColorData
  property stroke : ColorData
  property stroke_width : Float32
  property label : String?

  def initialize(e : RectElement)
    @type = "rect"
    @id   = e.id.to_s
    b = e.bounds
    @x, @y, @width, @height = b.x, b.y, b.width, b.height
    @fill         = ColorData.new(e.fill)
    @stroke       = ColorData.new(e.stroke)
    @stroke_width = e.stroke_width
    @label        = e.label
  end

  def to_element : Element
    bounds = R::Rectangle.new(x: @x, y: @y, width: @width, height: @height)
    RectElement.new(bounds, @fill.to_raylib, @stroke.to_raylib, @stroke_width, @label || "", UUID.new(@id))
  end
end

class TextElementData < ElementData
  include JSON::Serializable

  property type : String = "text"
  property id : String = UUID.random.to_s
  property x : Float32
  property y : Float32
  property width : Float32
  property height : Float32
  property text : String

  def initialize(e : TextElement)
    @type = "text"
    @id   = e.id.to_s
    b = e.bounds
    @x, @y, @width, @height = b.x, b.y, b.width, b.height
    @text = e.text
  end

  def to_element : Element
    bounds = R::Rectangle.new(x: @x, y: @y, width: @width, height: @height)
    TextElement.new(bounds, @text, UUID.new(@id))
  end
end

# ─── Reopen element classes to add persistence (avoids forward references) ────

# to_data is defined here rather than in element.cr so that element.cr stays
# free of references to the concrete data classes.

class RectElement
  def to_data : ElementData
    RectElementData.new(self)
  end
end

class TextElement
  def to_data : ElementData
    TextElementData.new(self)
  end
end

class ArrowElementData < ElementData
  include JSON::Serializable

  property type : String = "arrow"
  property id : String = UUID.random.to_s
  property from_id : String
  property to_id : String
  property routing_style : String = "orthogonal"

  def initialize(e : ArrowElement)
    @type          = "arrow"
    @id            = e.id.to_s
    @from_id       = e.from_id.to_s
    @to_id         = e.to_id.to_s
    @routing_style = e.routing_style.to_s.downcase
  end

  def to_element(elements : Array(Element)) : Element
    style = @routing_style == "straight" ? ArrowElement::RoutingStyle::Straight : ArrowElement::RoutingStyle::Orthogonal
    ArrowElement.new(UUID.new(@from_id), UUID.new(@to_id), elements, style, UUID.new(@id))
  end

  # Satisfy the abstract contract — callers that need the elements list use to_element(elements).
  def to_element : Element
    raise "ArrowElementData requires the elements array; call to_element(elements) instead"
  end
end

class ArrowElement
  def to_data : ElementData
    ArrowElementData.new(self)
  end
end
