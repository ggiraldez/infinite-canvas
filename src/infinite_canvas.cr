require "raylib-cr"
require "./app_font"
require "./canvas"
require "./toolbar"
require "./color_palette"

module InfiniteCanvas
  VERSION = "0.1.0"

  WINDOW_WIDTH  = 1280
  WINDOW_HEIGHT =  800
  TITLE         = "Infinite Canvas"

  def self.run
    R.set_config_flags(R::ConfigFlags::WindowResizable | R::ConfigFlags::MSAA4xHint)
    R.init_window(WINDOW_WIDTH, WINDOW_HEIGHT, TITLE)
    AppFont.load
    R.set_target_fps(60)
    R.set_exit_key(R::KeyboardKey::Null)

    canvas = Canvas.new(WINDOW_WIDTH, WINDOW_HEIGHT)
    canvas.load

    toolbar = Toolbar.new
    palette = ColorPalette.new

    smooth_update_ms = 0.0_f64
    smooth_draw_ms = 0.0_f64

    until R.close_window? || canvas.quit_requested?
      # Keep the camera offset pinned to the window centre when resized so
      # zoom and pan behave consistently.
      canvas.camera.offset = R::Vector2.new(
        x: R.get_screen_width / 2.0_f32,
        y: R.get_screen_height / 2.0_f32,
      )

      palette.update(canvas)
      toolbar.update(canvas)
      smooth_update_ms = timed_ema(smooth_update_ms) { canvas.update }

      R.begin_drawing
      R.clear_background(Canvas::BACKGROUND)
      smooth_draw_ms = timed_ema(smooth_draw_ms) { canvas.draw }
      draw_hud(canvas, toolbar, palette, smooth_update_ms, smooth_draw_ms)
      R.end_drawing
    end

    canvas.save
    R.close_window
  end

  # Times the block and returns an exponential moving average of elapsed ms.
  # α = 0.1 gives roughly a 10-frame smoothing window at 60 fps.
  private def self.timed_ema(smooth : Float64, &) : Float64
    t0 = Time.instant
    yield
    ms = (Time.instant - t0).total_milliseconds
    smooth * 0.9 + ms * 0.1
  end

  private def self.draw_hud(canvas : Canvas, toolbar : Toolbar, palette : ColorPalette, smooth_update_ms : Float64, smooth_draw_ms : Float64)
    toolbar.draw(canvas)
    palette.draw(canvas)
    AppFont.draw("Elements: #{canvas.elements.size}   Zoom: #{canvas.camera.zoom.round(2)}x", 12, 12, 20, R::GRAY)
    if (el = canvas.selected_element).is_a?(ArrowElement)
      AppFont.draw("Routing: #{el.routing_style}   [Tab]", 12, 36, 20, R::DARKGRAY)
    end
    timing_label = "update: #{smooth_update_ms.round(2)}ms  draw: #{smooth_draw_ms.round(2)}ms"
    label_w = AppFont.measure(timing_label, 20)
    AppFont.draw(timing_label, R.get_screen_width - 110 - label_w, R.get_screen_height - 30, 20, R::GRAY)
    R.draw_fps(R.get_screen_width - 100, R.get_screen_height - 30)
  end
end

InfiniteCanvas.run
