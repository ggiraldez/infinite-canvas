require "raylib-cr"
require "./font"
require "./canvas"
require "./toolbar"
require "./color_palette"
require "./smooth_timer"

module InfiniteCanvas
  VERSION = "0.1.0"

  WINDOW_WIDTH  = 1280
  WINDOW_HEIGHT =  800
  TITLE         = "Infinite Canvas"

  def self.run
    R.set_config_flags(R::ConfigFlags::WindowResizable | R::ConfigFlags::MSAA4xHint)
    R.init_window(WINDOW_WIDTH, WINDOW_HEIGHT, TITLE)
    font = Font.new("resources/Inter-Regular.ttf", 20)
    R.set_target_fps(60)
    R.set_exit_key(R::KeyboardKey::Null)

    canvas = Canvas.new(WINDOW_WIDTH, WINDOW_HEIGHT, font)
    canvas.load

    toolbar = Toolbar.new(font)
    palette = ColorPalette.new(font)

    update_time = SmoothTimer.new
    draw_time = SmoothTimer.new

    until R.close_window? || canvas.quit_requested?
      # Keep the camera offset pinned to the window centre when resized so
      # zoom and pan behave consistently.
      canvas.camera.offset = R::Vector2.new(
        x: R.get_screen_width / 2.0_f32,
        y: R.get_screen_height / 2.0_f32,
      )

      palette.update(canvas)
      toolbar.update(canvas)
      update_time.measure { canvas.update }

      R.begin_drawing
      R.clear_background(Canvas::BACKGROUND)
      draw_time.measure { canvas.draw }
      draw_hud(canvas, toolbar, palette, font, update_time.value, draw_time.value)
      R.end_drawing
    end

    canvas.save
    R.close_window
  end

  private def self.draw_hud(canvas : Canvas, toolbar : Toolbar, palette : ColorPalette, font : Font, update_ms : Float64, draw_ms : Float64)
    toolbar.draw(canvas)
    palette.draw(canvas)
    font.draw("Elements: #{canvas.elements.size}   Zoom: #{canvas.camera.zoom.round(2)}x", 12, 12, R::GRAY)
    if (el = canvas.selected_element).is_a?(ArrowElement)
      font.draw("Routing: #{el.routing_style}   [Tab]", 12, 36, R::DARKGRAY)
    end
    timing_label = "update: #{update_ms.round(2)}ms  draw: #{draw_ms.round(2)}ms"
    label_w = font.measure(timing_label)
    font.draw(timing_label, R.get_screen_width - 110 - label_w, R.get_screen_height - 30, R::GRAY)
    R.draw_fps(R.get_screen_width - 100, R.get_screen_height - 30)
  end
end

InfiniteCanvas.run
