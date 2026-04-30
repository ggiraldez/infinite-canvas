require "raylib-cr"
require "./font"
require "./canvas"
require "./events"
require "./model"

class ColorPalette
  def initialize(@font : Font)
  end
  struct Scheme
    getter name : String
    getter fill : ColorData
    getter stroke : ColorData
    getter label : ColorData

    def initialize(@name : String, @fill : ColorData, @stroke : ColorData, @label : ColorData); end
  end

  SWATCH_SIZE = 36
  GAP         =  6
  PANEL_P     =  8
  MARGIN_L    = 16

  BG          = R::Color.new(r: 255, g: 255, b: 255, a: 230)
  BORDER      = R::Color.new(r: 200, g: 200, b: 205, a: 255)
  ACTIVE_RING = R::Color.new(r: 0, g: 120, b: 255, a: 255)

  private def self.cd(r : Int32, g : Int32, b : Int32, a : Int32) : ColorData
    ColorData.new(r.to_u8, g.to_u8, b.to_u8, a.to_u8)
  end

  SCHEMES = [
    Scheme.new("Blue", cd(90, 140, 220, 200), cd(30, 60, 120, 255), cd(255, 255, 255, 230)),
    Scheme.new("Teal", cd(40, 180, 170, 200), cd(10, 100, 90, 255), cd(255, 255, 255, 230)),
    Scheme.new("Green", cd(70, 185, 90, 200), cd(20, 110, 40, 255), cd(255, 255, 255, 230)),
    Scheme.new("Yellow", cd(240, 200, 60, 200), cd(160, 125, 0, 255), cd(50, 40, 0, 230)),
    Scheme.new("Orange", cd(240, 140, 40, 200), cd(170, 80, 0, 255), cd(255, 255, 255, 230)),
    Scheme.new("Red", cd(220, 70, 70, 200), cd(150, 20, 20, 255), cd(255, 255, 255, 230)),
    Scheme.new("Pink", cd(220, 100, 180, 200), cd(160, 30, 120, 255), cd(255, 255, 255, 230)),
    Scheme.new("Purple", cd(140, 80, 220, 200), cd(70, 20, 150, 255), cd(255, 255, 255, 230)),
    Scheme.new("Gray", cd(140, 140, 150, 200), cd(70, 70, 80, 255), cd(255, 255, 255, 230)),
    Scheme.new("Dark", cd(50, 55, 65, 200), cd(20, 20, 25, 255), cd(255, 255, 255, 230)),
  ]

  # Returns true if the click was consumed by the palette.
  def update(canvas : Canvas) : Bool
    return false unless canvas.selected_element.is_a?(RectElement)
    return false unless R.mouse_button_pressed?(R::MouseButton::Left)
    mouse = R.get_mouse_position
    px, py = panel_origin

    SCHEMES.each_with_index do |scheme, i|
      if R.check_collision_point_rec?(mouse, swatch_rect(px, py, i))
        el = canvas.selected_element.as(RectElement)
        canvas.emit(ChangeRectColorEvent.new(el.id, scheme.fill, scheme.stroke, scheme.label))
        canvas.block_mouse_press
        return true
      end
    end

    if R.check_collision_point_rec?(mouse, panel_rect(px, py))
      canvas.block_mouse_press
      return true
    end

    false
  end

  def draw(canvas : Canvas) : Nil
    return unless (el = canvas.selected_element).is_a?(RectElement)
    px, py = panel_origin
    R.draw_rectangle_rec(panel_rect(px, py), BG)
    R.draw_rectangle_lines_ex(panel_rect(px, py), 1.0_f32, BORDER)

    font_size = 20
    aw = @font.measure("A", font_size)
    SCHEMES.each_with_index do |scheme, i|
      rect = swatch_rect(px, py, i)
      R.draw_rectangle_rec(rect, scheme.fill.to_raylib)
      R.draw_rectangle_lines_ex(rect, 1.5_f32, scheme.stroke.to_raylib)
      @font.draw("A",
        (rect.x + (rect.width - aw) / 2).to_i,
        (rect.y + (rect.height - font_size) / 2).to_i,
        font_size, scheme.label.to_raylib)
      if active_scheme?(el, scheme)
        exp = 3.0_f32
        ring = R::Rectangle.new(x: rect.x - exp, y: rect.y - exp,
          width: rect.width + exp * 2, height: rect.height + exp * 2)
        R.draw_rectangle_lines_ex(ring, 2.5_f32, ACTIVE_RING)
      end
    end
  end

  private def active_scheme?(el : RectElement, scheme : Scheme) : Bool
    f = ColorData.new(el.fill)
    f.r == scheme.fill.r && f.g == scheme.fill.g && f.b == scheme.fill.b
  end

  private def panel_origin : {Int32, Int32}
    total_h = SCHEMES.size * SWATCH_SIZE + (SCHEMES.size - 1) * GAP + 2 * PANEL_P
    py = (R.get_screen_height - total_h) // 2
    {MARGIN_L, py}
  end

  private def panel_rect(px : Int32, py : Int32) : R::Rectangle
    total_h = SCHEMES.size * SWATCH_SIZE + (SCHEMES.size - 1) * GAP + 2 * PANEL_P
    R::Rectangle.new(x: px.to_f32, y: py.to_f32,
      width: (SWATCH_SIZE + 2 * PANEL_P).to_f32, height: total_h.to_f32)
  end

  private def swatch_rect(px : Int32, py : Int32, i : Int32) : R::Rectangle
    R::Rectangle.new(
      x: (px + PANEL_P).to_f32,
      y: (py + PANEL_P + i * (SWATCH_SIZE + GAP)).to_f32,
      width: SWATCH_SIZE.to_f32, height: SWATCH_SIZE.to_f32)
  end
end
