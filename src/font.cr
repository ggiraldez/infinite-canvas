require "raylib-cr"

class Font
  @font : Raylib::Font
  getter size : Int32
  getter spacing : Float32

  def initialize(path : String, @size : Int32, @spacing : Float32 = 0.0_f32)
    f = Raylib.load_font_ex(path, @size, nil, 0)
    Raylib.set_texture_filter(f.texture, Raylib::TextureFilter::Bilinear)
    @font = f
  end

  def draw(text : String, x : Number, y : Number, color : Raylib::Color)
    Raylib.draw_text_ex(@font, text, Raylib::Vector2.new(x: x.to_f32, y: y.to_f32), @size.to_f32, @spacing, color)
  end

  def measure(text : String) : Int32
    Raylib.measure_text_ex(@font, text, @size.to_f32, @spacing).x.to_i
  end
end
