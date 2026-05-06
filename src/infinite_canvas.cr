require "raylib-cr"
require "./font"
require "./canvas"
require "./smooth_timer"
require "./controls"

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

    controls = Controls.new(font)

    update_time = SmoothTimer.new
    draw_time = SmoothTimer.new

    until R.close_window? || canvas.quit_requested?
      # Keep the camera offset pinned to the window centre when resized so
      # zoom and pan behave consistently.
      canvas.camera.offset = R::Vector2.new(
        x: R.get_screen_width / 2.0_f32,
        y: R.get_screen_height / 2.0_f32,
      )

      update_time.measure do
        click_consumed = controls.handle_left_press(canvas)
        canvas.handle_input(click_consumed)
      end

      R.begin_drawing
      draw_time.measure do
        R.clear_background(Canvas::BACKGROUND)
        canvas.draw
        controls.draw(canvas)
      end
      draw_timing(font, update_time.value, draw_time.value)
      R.end_drawing
    end

    canvas.save
    R.close_window
  end

  def self.draw_timing(font : Font, update_ms : Float64, draw_ms : Float64)
    timing_label = "update: #{update_ms.round(2)}ms  draw: #{draw_ms.round(2)}ms"
    label_w = font.measure(timing_label)
    font.draw(timing_label, R.get_screen_width - 110 - label_w, R.get_screen_height - 30, R::GRAY)
    R.draw_fps(R.get_screen_width - 100, R.get_screen_height - 30)
  end
end

InfiniteCanvas.run
