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

  # Whether the element can be manually resized by dragging handles.
  # Text nodes return false — their size is always derived from their content.
  def resizable? : Bool
    true
  end

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

  def resizable? : Bool
    false
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
    if text.empty?
      # Reserve enough space for the blinking cursor with padding on all sides,
      # so a freshly-created text node looks intentional rather than invisible.
      cursor_w = R.measure_text("|", FONT_SIZE)
      return {(cursor_w + PADDING * 2).to_f32, (FONT_SIZE + PADDING * 2).to_f32}
    end
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
    # Text nodes are always sized to exactly fit their content — never larger.
    @bounds = R::Rectangle.new(x: bounds.x, y: bounds.y, width: mw, height: mh)
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

# ─── Arrow ────────────────────────────────────────────────────────────────────

# A directional arrow connecting two other elements by their UUIDs.
# Endpoints are resolved at draw-time from the shared elements array so the
# arrow automatically tracks elements as they move.
class ArrowElement < Element
  ARROW_COLOR    = R::Color.new(r: 60, g: 60, b: 60, a: 220)
  ARROW_WIDTH    = 2.0_f32
  ARROWHEAD_LEN  = 14.0_f32
  ARROWHEAD_HALF =  5.0_f32

  property from_id : UUID
  property to_id : UUID

  # Reference to the canvas element list — updated at construction so the
  # arrow can resolve from_id / to_id without coupling to Canvas directly.
  property elements : Array(Element)

  def initialize(@from_id : UUID, @to_id : UUID, @elements : Array(Element), id : UUID = UUID.random)
    super(R::Rectangle.new(x: 0.0_f32, y: 0.0_f32, width: 0.0_f32, height: 0.0_f32), id)
  end

  def resizable? : Bool
    false
  end

  # Arrows are not hit-tested via the normal bounding-rect check.
  # Canvas calls near_line? instead so it can supply the zoom-aware threshold.
  def contains?(world_point : R::Vector2) : Bool
    false
  end

  # Returns true when *world_point* is within *threshold* world units of the
  # arrow shaft.  Canvas divides a fixed screen-pixel constant by zoom before
  # calling this so the click target stays constant in screen space.
  def near_line?(world_point : R::Vector2, threshold : Float32) : Bool
    from_el = resolve_from
    to_el   = resolve_to
    return false unless from_el && to_el
    a, b = endpoints(from_el, to_el)
    segment_dist(world_point, a, b) <= threshold
  end

  def draw
    from_el = resolve_from
    to_el   = resolve_to
    return unless from_el && to_el
    a, b = endpoints(from_el, to_el)
    draw_arrow(a, b, ARROW_COLOR, ARROW_WIDTH)
    update_bounds(a, b)
  end

  # Draws the arrow in *color* at *width* — used by Canvas for the selection
  # highlight without re-resolving elements a second time.
  def draw_highlighted(color : R::Color, width : Float32)
    from_el = resolve_from
    to_el   = resolve_to
    return unless from_el && to_el
    a, b = endpoints(from_el, to_el)
    draw_arrow(a, b, color, width)
  end

  private def resolve_from : Element?
    @elements.find { |e| e.id == @from_id }
  end

  private def resolve_to : Element?
    @elements.find { |e| e.id == @to_id }
  end

  # Returns the two world-space points where the arrow shaft meets each element's border.
  private def endpoints(from_el : Element, to_el : Element) : {R::Vector2, R::Vector2}
    fc = center_of(from_el.bounds)
    tc = center_of(to_el.bounds)
    {border_exit_point(from_el.bounds, fc, tc), border_exit_point(to_el.bounds, tc, fc)}
  end

  private def center_of(b : R::Rectangle) : R::Vector2
    R::Vector2.new(x: b.x + b.width / 2.0_f32, y: b.y + b.height / 2.0_f32)
  end

  # Returns the point where the ray from *origin* (the centre of *b*) toward
  # *toward* exits the border of rectangle *b*.  Falls back to origin when the
  # two centres are coincident.
  private def border_exit_point(b : R::Rectangle, origin : R::Vector2, toward : R::Vector2) : R::Vector2
    dx = toward.x - origin.x
    dy = toward.y - origin.y
    return origin if dx.abs < 0.001_f32 && dy.abs < 0.001_f32

    t_min = Float32::MAX

    # Right edge
    if dx > 0.001_f32
      t = (b.x + b.width - origin.x) / dx
      y = origin.y + t * dy
      t_min = t if t >= 0 && y >= b.y && y <= b.y + b.height && t < t_min
    end
    # Left edge
    if dx < -0.001_f32
      t = (b.x - origin.x) / dx
      y = origin.y + t * dy
      t_min = t if t >= 0 && y >= b.y && y <= b.y + b.height && t < t_min
    end
    # Bottom edge
    if dy > 0.001_f32
      t = (b.y + b.height - origin.y) / dy
      x = origin.x + t * dx
      t_min = t if t >= 0 && x >= b.x && x <= b.x + b.width && t < t_min
    end
    # Top edge
    if dy < -0.001_f32
      t = (b.y - origin.y) / dy
      x = origin.x + t * dx
      t_min = t if t >= 0 && x >= b.x && x <= b.x + b.width && t < t_min
    end

    if t_min < Float32::MAX
      R::Vector2.new(x: origin.x + t_min * dx, y: origin.y + t_min * dy)
    else
      origin
    end
  end

  private def update_bounds(a : R::Vector2, b : R::Vector2)
    x = Math.min(a.x, b.x)
    y = Math.min(a.y, b.y)
    w = [(a.x - b.x).abs, 1.0_f32].max
    h = [(a.y - b.y).abs, 1.0_f32].max
    @bounds = R::Rectangle.new(x: x, y: y, width: w, height: h)
  end

  private def draw_arrow(a : R::Vector2, b : R::Vector2, color : R::Color, width : Float32)
    dx = b.x - a.x
    dy = b.y - a.y
    len = Math.sqrt(dx * dx + dy * dy).to_f32
    return if len < 1.0_f32

    ux = dx / len  # unit direction
    uy = dy / len
    px = -uy       # perpendicular (left-hand side)
    py =  ux

    # Shaft stops just before the arrowhead base.
    shaft_tip_x = b.x - ux * ARROWHEAD_LEN
    shaft_tip_y = b.y - uy * ARROWHEAD_LEN
    shaft_tip = R::Vector2.new(x: shaft_tip_x, y: shaft_tip_y)
    R.draw_line_ex(a, shaft_tip, width, color)

    # Filled arrowhead triangle (tip → left-base → right-base, CCW in screen Y-down).
    tip   = b
    left  = R::Vector2.new(x: shaft_tip_x + px * ARROWHEAD_HALF, y: shaft_tip_y + py * ARROWHEAD_HALF)
    right = R::Vector2.new(x: shaft_tip_x - px * ARROWHEAD_HALF, y: shaft_tip_y - py * ARROWHEAD_HALF)
    R.draw_triangle(tip, right, left, color)
  end

  # Minimum distance from point *p* to line segment *a*–*b*.
  private def segment_dist(p : R::Vector2, a : R::Vector2, b : R::Vector2) : Float32
    dx = b.x - a.x
    dy = b.y - a.y
    len_sq = dx * dx + dy * dy
    if len_sq < 0.001_f32
      return Math.sqrt((p.x - a.x)**2 + (p.y - a.y)**2).to_f32
    end
    t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len_sq
    t = t.clamp(0.0_f32, 1.0_f32)
    proj_x = a.x + t * dx
    proj_y = a.y + t * dy
    Math.sqrt((p.x - proj_x)**2 + (p.y - proj_y)**2).to_f32
  end
end
