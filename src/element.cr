require "raylib-cr"

alias R = Raylib

# Base class for anything that lives on the canvas.
# Positions and sizes are in world space (not screen space).
abstract class Element
  property bounds : R::Rectangle

  def initialize(@bounds : R::Rectangle)
  end

  abstract def draw

  def contains?(world_point : R::Vector2) : Bool
    R.check_collision_point_rec?(world_point, bounds)
  end
end

class RectElement < Element
  property fill : R::Color
  property stroke : R::Color
  property stroke_width : Float32

  def initialize(bounds : R::Rectangle,
                 @fill : R::Color = R::Color.new(r: 90, g: 140, b: 220, a: 200),
                 @stroke : R::Color = R::Color.new(r: 30, g: 60, b: 120, a: 255),
                 @stroke_width : Float32 = 2.0_f32)
    super(bounds)
  end

  def draw
    R.draw_rectangle_rec(bounds, fill)
    R.draw_rectangle_lines_ex(bounds, stroke_width, stroke)
  end
end
