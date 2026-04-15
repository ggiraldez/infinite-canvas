require "raylib-cr"
require "./canvas"

module InfiniteCanvas
  VERSION = "0.1.0"

  WINDOW_WIDTH  = 1280
  WINDOW_HEIGHT =  800
  TITLE         = "Infinite Canvas"

  def self.run
    R.set_config_flags(R::ConfigFlags::WindowResizable | R::ConfigFlags::MSAA4xHint)
    R.init_window(WINDOW_WIDTH, WINDOW_HEIGHT, TITLE)
    R.set_target_fps(60)

    canvas = Canvas.new(WINDOW_WIDTH, WINDOW_HEIGHT)
    canvas.load

    smooth_draw_ms = 0.0_f64

    until R.close_window?
      # Keep the camera offset pinned to the window centre when resized so
      # zoom and pan behave consistently.
      canvas.camera.offset = R::Vector2.new(
        x: R.get_screen_width / 2.0_f32,
        y: R.get_screen_height / 2.0_f32,
      )

      canvas.update

      R.begin_drawing
      R.clear_background(Canvas::BACKGROUND)
      t0 = Time.instant
      canvas.draw
      draw_ms = (Time.instant - t0).total_milliseconds
      smooth_draw_ms = smooth_draw_ms * 0.9 + draw_ms * 0.1
      draw_hud(canvas, smooth_draw_ms)
      R.end_drawing
    end

    canvas.save
    R.close_window
  end

  private def self.draw_hud(canvas : Canvas, smooth_draw_ms : Float64)
    R.draw_text("Tools: [S]elect  [R]ect  [T]ext  [A]rrow   active: #{canvas.active_tool}   |   Delete: Del", 12, 12, 20, R::DARKGRAY)
    R.draw_text("Pan: right/middle-drag   Zoom: wheel   Elements: #{canvas.elements.size}   Zoom: #{canvas.camera.zoom.round(2)}x", 12, 36, 20, R::GRAY)
    if (el = canvas.selected_element).is_a?(ArrowElement)
      R.draw_text("Arrow routing: #{el.routing_style}   [Tab] to toggle", 12, 60, 20, R::DARKGRAY)
    end
    draw_label = "draw: #{smooth_draw_ms.round(2)}ms"
    label_w = R.measure_text(draw_label, 20)
    R.draw_text(draw_label, R.get_screen_width - 110 - label_w, R.get_screen_height - 30, 20, R::GRAY)
    R.draw_fps(R.get_screen_width - 100, R.get_screen_height - 30)
  end
end

InfiniteCanvas.run
