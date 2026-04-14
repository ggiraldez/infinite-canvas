require "raylib-cr"
require "uuid"

alias R = Raylib

# Abstract base for element serialisation data — concrete types defined in persistence.cr.
abstract class ElementData
  abstract def to_element : Element
end

# Base class for anything that lives on the canvas.
# Positions and sizes are in world space (not screen space).
abstract class Element
  property bounds : R::Rectangle
  getter id : UUID

  def initialize(@bounds : R::Rectangle, @id : UUID = UUID.random)
  end

  abstract def draw

  def contains?(world_point : R::Vector2) : Bool
    R.check_collision_point_rec?(world_point, bounds)
  end

  # Minimum dimensions required to display this element's content without clipping.
  # Subclasses override to account for text or other content.
  def min_size : {Float32, Float32}
    {4.0_f32, 4.0_f32}
  end

  # Called once per printable character pressed while this element is selected.
  def handle_char_input(ch : Char); end

  # Called when Enter is pressed while this element is selected.
  def handle_enter; end

  # Called when Backspace is pressed while this element is selected.
  def handle_backspace; end

  # Expands bounds if content no longer fits after a text change.
  def fit_content; end

  # Draws a blinking text cursor while this element is selected.
  # Called inside begin_mode_2d, so coordinates are world space.
  def draw_cursor; end
end

# ─── Rectangle ────────────────────────────────────────────────────────────────

class RectElement < Element
  LABEL_FONT_SIZE = 20
  LABEL_COLOR     = R::Color.new(r: 255, g: 255, b: 255, a: 230)
  LABEL_PADDING_H = 16  # minimum horizontal padding on each side
  LABEL_PADDING_V = 12  # minimum vertical padding on each side

  property fill : R::Color
  property stroke : R::Color
  property stroke_width : Float32
  property label : String

  def initialize(bounds : R::Rectangle,
                 @fill : R::Color = R::Color.new(r: 90, g: 140, b: 220, a: 200),
                 @stroke : R::Color = R::Color.new(r: 30, g: 60, b: 120, a: 255),
                 @stroke_width : Float32 = 2.0_f32,
                 @label : String = "",
                 id : UUID = UUID.random)
    super(bounds, id)
  end

  def draw
    R.draw_rectangle_rec(bounds, fill)
    R.draw_rectangle_lines_ex(bounds, stroke_width, stroke)
    draw_centered_text(label)
  end

  def min_size : {Float32, Float32}
    {label_min_width, label_min_height}
  end

  def handle_char_input(ch : Char)
    @label += ch.to_s
  end

  def handle_enter
    @label += "\n"
  end

  def handle_backspace
    @label = @label.rchop
  end

  def fit_content
    fit_label
  end

  def draw_cursor
    return unless (R.get_time * 2.0).to_i % 2 == 0
    lines = label.split('\n')
    last_line = lines.last
    tw = R.measure_text(last_line, LABEL_FONT_SIZE)
    total_height = lines.size * LABEL_FONT_SIZE
    cx = (bounds.x + (bounds.width + tw) / 2.0_f32).to_i
    cy = (bounds.y + (bounds.height - total_height) / 2.0_f32 + (lines.size - 1) * LABEL_FONT_SIZE).to_i
    R.draw_text("|", cx, cy, LABEL_FONT_SIZE, LABEL_COLOR)
  end

  # Minimum width needed to display the current label without clipping.
  # Returns 4.0 when the label is empty so the bare minimum size is unchanged.
  def label_min_width : Float32
    return 4.0_f32 if label.empty?
    lines = label.split('\n')
    max_tw = lines.map { |l| R.measure_text(l, LABEL_FONT_SIZE) }.max? || 0
    (max_tw + LABEL_PADDING_H * 2).to_f32
  end

  # Minimum height needed to display the current label without clipping.
  # Returns 4.0 when the label is empty so the bare minimum size is unchanged.
  def label_min_height : Float32
    return 4.0_f32 if label.empty?
    lines = label.split('\n')
    (lines.size * LABEL_FONT_SIZE + LABEL_PADDING_V * 2).to_f32
  end

  # Expands bounds in-place so the label fits, never shrinks.
  def fit_label
    new_w = Math.max(bounds.width, label_min_width)
    new_h = Math.max(bounds.height, label_min_height)
    @bounds = R::Rectangle.new(x: bounds.x, y: bounds.y, width: new_w, height: new_h)
  end

  # Draws *text* horizontally and vertically centred inside bounds.
  # Newline characters split the text into multiple centred lines.
  def draw_centered_text(text : String)
    return if text.empty?
    lines = text.split('\n')
    total_height = lines.size * LABEL_FONT_SIZE
    start_y = bounds.y + (bounds.height - total_height) / 2.0_f32
    lines.each_with_index do |line, i|
      tw = R.measure_text(line, LABEL_FONT_SIZE)
      lx = (bounds.x + (bounds.width - tw) / 2.0_f32).to_i
      ly = (start_y + i * LABEL_FONT_SIZE).to_i
      R.draw_text(line, lx, ly, LABEL_FONT_SIZE, LABEL_COLOR)
    end
  end
end

# ─── Text node ────────────────────────────────────────────────────────────────

# A plain text node: no background rectangle, text top-left aligned within bounds.
class TextElement < Element
  FONT_SIZE  = 20
  TEXT_COLOR = R::Color.new(r: 30, g: 30, b: 30, a: 255)
  PADDING    =  8  # padding on each side in world units

  property text : String

  def initialize(bounds : R::Rectangle, @text : String = "", id : UUID = UUID.random)
    super(bounds, id)
  end

  def draw
    return if text.empty?
    lines = text.split('\n')
    lines.each_with_index do |line, i|
      R.draw_text(line,
        bounds.x.to_i + PADDING,
        (bounds.y + PADDING + i * FONT_SIZE).to_i,
        FONT_SIZE, TEXT_COLOR)
    end
  end

  def min_size : {Float32, Float32}
    return {4.0_f32, 4.0_f32} if text.empty?
    lines = text.split('\n')
    max_tw = lines.map { |l| R.measure_text(l, FONT_SIZE) }.max? || 0
    {(max_tw + PADDING * 2).to_f32, (lines.size * FONT_SIZE + PADDING * 2).to_f32}
  end

  def handle_char_input(ch : Char)
    @text += ch.to_s
  end

  def handle_enter
    @text += "\n"
  end

  def handle_backspace
    @text = @text.rchop
  end

  def fit_content
    mw, mh = min_size
    @bounds = R::Rectangle.new(
      x: bounds.x, y: bounds.y,
      width: Math.max(bounds.width, mw),
      height: Math.max(bounds.height, mh),
    )
  end

  def draw_cursor
    return unless (R.get_time * 2.0).to_i % 2 == 0
    lines = text.split('\n')
    last_line = lines.last
    tw = R.measure_text(last_line, FONT_SIZE)
    cx = bounds.x.to_i + PADDING + tw
    cy = (bounds.y + PADDING + (lines.size - 1) * FONT_SIZE).to_i
    R.draw_text("|", cx, cy, FONT_SIZE, TEXT_COLOR)
  end
end
