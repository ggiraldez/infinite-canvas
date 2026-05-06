require "./font"
require "./toolbar"
require "./color_palette"

class Controls
  def initialize(@font : Font)
    @toolbar = Toolbar.new(@font)
    @palette = ColorPalette.new(@font)
  end

  # Checks for presses with the left mouse button. Returns true if a click was consumed.
  def handle_left_press(canvas : Canvas) : Bool
    @toolbar.handle_left_press(canvas) || @palette.handle_left_press(canvas)
  end

  def draw(canvas : Canvas)
    @toolbar.draw(canvas)
    @palette.draw(canvas)
    @font.draw("Elements: #{canvas.elements.size}   Zoom: #{canvas.camera.zoom.round(2)}x", 12, 12, R::GRAY)
    if (el = canvas.selected_element).is_a?(ArrowElement)
      @font.draw("Routing: #{el.routing_style}   [Tab]", 12, 36, R::DARKGRAY)
    end
  end
end
