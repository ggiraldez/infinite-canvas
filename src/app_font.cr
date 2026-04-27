require "raylib-cr"

# Global font loaded once after the Raylib window opens.
# Call AppFont.load immediately after R.init_window; all other methods
# fall back to the Raylib default font if called before that.
module AppFont
  @@font : Raylib::Font? = nil

  def self.load
    font = Raylib.load_font_ex("resources/Inter-Regular.ttf", 20, nil, 0)
    Raylib.set_texture_filter(font.texture, Raylib::TextureFilter::Bilinear)
    @@font = font
  end

  def self.draw(text : String, x : Number, y : Number, font_size : Number, color : Raylib::Color)
    if (f = @@font)
      Raylib.draw_text_ex(f, text, Raylib::Vector2.new(x: x.to_f32, y: y.to_f32), font_size.to_f32, spacing(font_size.to_i), color)
    else
      Raylib.draw_text(text, x.to_i, y.to_i, font_size.to_i, color)
    end
  end

  def self.measure(text : String, font_size : Number) : Int32
    if (f = @@font)
      Raylib.measure_text_ex(f, text, font_size.to_f32, spacing(font_size.to_i)).x.to_i
    else
      Raylib.measure_text(text, font_size.to_i)
    end
  end

  private def self.spacing(font_size : Int32) : Float32
    0.0_f32
  end
end
