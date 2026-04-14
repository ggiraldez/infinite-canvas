require "json"
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

# JSON-serializable mirror of a RectElement.
struct RectElementData
  include JSON::Serializable

  property x : Float32
  property y : Float32
  property width : Float32
  property height : Float32
  property fill : ColorData
  property stroke : ColorData
  property stroke_width : Float32
  property label : String?

  def initialize(e : RectElement)
    b = e.bounds
    @x, @y, @width, @height = b.x, b.y, b.width, b.height
    @fill         = ColorData.new(e.fill)
    @stroke       = ColorData.new(e.stroke)
    @stroke_width = e.stroke_width
    @label        = e.label
  end

  def to_element : RectElement
    bounds = R::Rectangle.new(x: @x, y: @y, width: @width, height: @height)
    RectElement.new(bounds, @fill.to_raylib, @stroke.to_raylib, @stroke_width, @label || "")
  end
end

# Top-level save file structure.
struct CanvasSaveData
  include JSON::Serializable

  property rects : Array(RectElementData)

  def initialize(@rects : Array(RectElementData))
  end
end
