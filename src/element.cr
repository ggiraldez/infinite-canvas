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
  LABEL_FONT_SIZE = 20
  LABEL_COLOR     = R::Color.new(r: 255, g: 255, b: 255, a: 230)

  property fill : R::Color
  property stroke : R::Color
  property stroke_width : Float32
  property label : String

  def initialize(bounds : R::Rectangle,
                 @fill : R::Color = R::Color.new(r: 90, g: 140, b: 220, a: 200),
                 @stroke : R::Color = R::Color.new(r: 30, g: 60, b: 120, a: 255),
                 @stroke_width : Float32 = 2.0_f32,
                 @label : String = "")
    super(bounds)
  end

  def draw
    R.draw_rectangle_rec(bounds, fill)
    R.draw_rectangle_lines_ex(bounds, stroke_width, stroke)
    draw_centered_text(label)
  end

  # Draws *text* horizontally and vertically centred inside bounds.
  def draw_centered_text(text : String)
    return if text.empty?
    tw = R.measure_text(text, LABEL_FONT_SIZE)
    lx = (bounds.x + (bounds.width - tw) / 2.0_f32).to_i
    ly = (bounds.y + (bounds.height - LABEL_FONT_SIZE) / 2.0_f32).to_i
    R.draw_text(text, lx, ly, LABEL_FONT_SIZE, LABEL_COLOR)
  end
end
