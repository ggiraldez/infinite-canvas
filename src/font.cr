require "raylib-cr"

class Font
  @font : Raylib::Font

  def initialize(path : String, size : Int32)
    f = Raylib.load_font_ex(path, size, nil, 0)
    Raylib.set_texture_filter(f.texture, Raylib::TextureFilter::Bilinear)
    @font = f
  end

  def draw(text : String, x : Number, y : Number, font_size : Number, color : Raylib::Color)
    Raylib.draw_text_ex(@font, text, Raylib::Vector2.new(x: x.to_f32, y: y.to_f32), font_size.to_f32, 0.0_f32, color)
  end

  def measure(text : String, font_size : Number) : Int32
    Raylib.measure_text_ex(@font, text, font_size.to_f32, 0.0_f32).x.to_i
  end
end
