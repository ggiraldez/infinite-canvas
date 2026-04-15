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

  enum RoutingStyle
    Straight
    Orthogonal
  end

  property from_id : UUID
  property to_id : UUID
  property routing_style : RoutingStyle

  # Reference to the canvas element list — updated at construction so the
  # arrow can resolve from_id / to_id without coupling to Canvas directly.
  property elements : Array(Element)

  def initialize(@from_id : UUID, @to_id : UUID, @elements : Array(Element),
                 @routing_style : RoutingStyle = RoutingStyle::Orthogonal,
                 id : UUID = UUID.random)
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

  # Returns true when *world_point* is within *threshold* world units of any
  # segment of the arrow.  Canvas divides a fixed screen-pixel constant by zoom
  # before calling this so the click target is constant in screen space.
  def near_line?(world_point : R::Vector2, threshold : Float32) : Bool
    from_el = resolve_from
    to_el   = resolve_to
    return false unless from_el && to_el
    pts = route(from_el.bounds, to_el.bounds)
    (pts.size - 1).times.any? { |i| segment_dist(world_point, pts[i], pts[i + 1]) <= threshold }
  end

  def draw
    from_el = resolve_from
    to_el   = resolve_to
    return unless from_el && to_el
    pts = route(from_el.bounds, to_el.bounds)
    draw_segments(pts, ARROW_COLOR, ARROW_WIDTH)
    update_bounds_from_points(pts)
  end

  # Draws the arrow in *color* at *width* — used by Canvas for the selection highlight.
  def draw_highlighted(color : R::Color, width : Float32)
    from_el = resolve_from
    to_el   = resolve_to
    return unless from_el && to_el
    draw_segments(route(from_el.bounds, to_el.bounds), color, width)
  end

  private def resolve_from : Element?
    @elements.find { |e| e.id == @from_id }
  end

  private def resolve_to : Element?
    @elements.find { |e| e.id == @to_id }
  end

  # ── Routing ──────────────────────────────────────────────────────────────────

  private def route(src : R::Rectangle, tgt : R::Rectangle) : Array(R::Vector2)
    @routing_style.straight? ? straight_route(src, tgt) : ortho_route(src, tgt)
  end

  # Straight: two border points on the centre-to-centre line.
  private def straight_route(src : R::Rectangle, tgt : R::Rectangle) : Array(R::Vector2)
    src_c = R::Vector2.new(x: src.x + src.width / 2.0_f32, y: src.y + src.height / 2.0_f32)
    tgt_c = R::Vector2.new(x: tgt.x + tgt.width / 2.0_f32, y: tgt.y + tgt.height / 2.0_f32)
    [border_exit_point(src, src_c, tgt_c), border_exit_point(tgt, tgt_c, src_c)]
  end

  # ── Orthogonal routing ───────────────────────────────────────────────────────

  # Returns an ordered list of waypoints for an orthogonal (rectilinear) path
  # from the border of *src* to the border of *tgt*.
  #
  # Strategy:
  #   1. Determine which sides will be used (via natural_sides).
  #   2. Compute a spread fraction for each endpoint so that multiple arrows
  #      sharing the same side fan out evenly rather than all bunching at centre.
  #   3. Try a 2-segment L-shape (Option A: horizontal exit / vertical entry, or
  #      Option B: vertical exit / horizontal entry).  Valid when the shared corner
  #      lies outside both rectangles so no segment doubles back.
  #   4. Fall back to a 3-segment Z-shape (facing borders) or U-shape (opposing).
  private def ortho_route(src : R::Rectangle, tgt : R::Rectangle) : Array(R::Vector2)
    sx = src.x + src.width  / 2.0_f32
    sy = src.y + src.height / 2.0_f32
    tx = tgt.x + tgt.width  / 2.0_f32
    ty = tgt.y + tgt.height / 2.0_f32
    dx = tx - sx
    dy = ty - sy

    from_side, to_side = natural_sides(src, tgt, dx, dy)
    frac_src = side_fraction(@from_id, true,  from_side, src)
    frac_tgt = side_fraction(@to_id,   false, to_side,   tgt)

    # Spread coordinates along each side.
    # Left/Right sides → fraction varies along y; Top/Bottom sides → along x.
    exit_y  = src.y + frac_src * src.height  # used when from_side is Left or Right
    exit_x  = src.x + frac_src * src.width   # used when from_side is Top or Bottom
    entry_x = tgt.x + frac_tgt * tgt.width   # used when to_side is Top or Bottom
    entry_y = tgt.y + frac_tgt * tgt.height  # used when to_side is Left or Right

    # ── L-shape attempts (2 segments) ────────────────────────────────────────
    if dx.abs > 0.5_f32 && dy.abs > 0.5_f32
      # Option A: exit src from horizontal border (L/R), enter tgt from vertical (T/B).
      ex_a  = dx > 0 ? src.x + src.width : src.x
      ey_a  = dy > 0 ? tgt.y : tgt.y + tgt.height
      seg1a = dx > 0 ? entry_x > ex_a : entry_x < ex_a
      seg2a = dy > 0 ? ey_a > exit_y  : ey_a < exit_y
      if seg1a && seg2a
        return [R::Vector2.new(x: ex_a,    y: exit_y),
                R::Vector2.new(x: entry_x, y: exit_y),
                R::Vector2.new(x: entry_x, y: ey_a)]
      end

      # Option B: exit src from vertical border (T/B), enter tgt from horizontal (L/R).
      ey_b  = dy > 0 ? src.y + src.height : src.y
      ex_b  = dx > 0 ? tgt.x : tgt.x + tgt.width
      seg1b = dy > 0 ? entry_y > ey_b : entry_y < ey_b
      seg2b = dx > 0 ? ex_b > exit_x  : ex_b < exit_x
      if seg1b && seg2b
        return [R::Vector2.new(x: exit_x, y: ey_b),
                R::Vector2.new(x: exit_x, y: entry_y),
                R::Vector2.new(x: ex_b,   y: entry_y)]
      end
    end

    # ── 3-segment fallback ────────────────────────────────────────────────────
    a = exit_point_on_side(from_side, src, frac_src)
    b = exit_point_on_side(to_side,   tgt, frac_tgt)

    case {from_side, to_side}
    when {Side::Right, Side::Left}, {Side::Left, Side::Right}
      mid_x = (a.x + b.x) / 2.0_f32
      [a, R::Vector2.new(x: mid_x, y: a.y), R::Vector2.new(x: mid_x, y: b.y), b]
    when {Side::Top, Side::Bottom}, {Side::Bottom, Side::Top}
      mid_y = (a.y + b.y) / 2.0_f32
      [a, R::Vector2.new(x: a.x, y: mid_y), R::Vector2.new(x: b.x, y: mid_y), b]
    when {Side::Right, Side::Right}
      ext = [a.x, b.x].max + 30.0_f32
      [a, R::Vector2.new(x: ext, y: a.y), R::Vector2.new(x: ext, y: b.y), b]
    when {Side::Left, Side::Left}
      ext = [a.x, b.x].min - 30.0_f32
      [a, R::Vector2.new(x: ext, y: a.y), R::Vector2.new(x: ext, y: b.y), b]
    when {Side::Bottom, Side::Bottom}
      ext = [a.y, b.y].max + 30.0_f32
      [a, R::Vector2.new(x: a.x, y: ext), R::Vector2.new(x: b.x, y: ext), b]
    when {Side::Top, Side::Top}
      ext = [a.y, b.y].min - 30.0_f32
      [a, R::Vector2.new(x: a.x, y: ext), R::Vector2.new(x: b.x, y: ext), b]
    else
      [a, R::Vector2.new(x: b.x, y: a.y), b]
    end
  end

  # Predicts which border sides the arrow will use for *src* (exit) and *tgt*
  # (entry), applying the same Option A / Option B / fallback decision tree as
  # ortho_route — but without computing the full path.  Used by side_fraction
  # to group sibling arrows that share a side.
  private def natural_sides(src : R::Rectangle, tgt : R::Rectangle,
                             dx : Float32, dy : Float32) : {Side, Side}
    sx = src.x + src.width  / 2.0_f32
    sy = src.y + src.height / 2.0_f32
    tx = tgt.x + tgt.width  / 2.0_f32
    ty = tgt.y + tgt.height / 2.0_f32

    if dx.abs > 0.5_f32 && dy.abs > 0.5_f32
      # Option A: horizontal exit from src, vertical entry to tgt
      ex_a  = dx > 0 ? src.x + src.width : src.x
      ey_a  = dy > 0 ? tgt.y : tgt.y + tgt.height
      seg1a = dx > 0 ? tx > ex_a : tx < ex_a
      seg2a = dy > 0 ? ey_a > sy : ey_a < sy
      if seg1a && seg2a
        from_s = dx > 0 ? Side::Right : Side::Left
        to_s   = dy > 0 ? Side::Top   : Side::Bottom
        return {from_s, to_s}
      end

      # Option B: vertical exit from src, horizontal entry to tgt
      ey_b  = dy > 0 ? src.y + src.height : src.y
      ex_b  = dx > 0 ? tgt.x : tgt.x + tgt.width
      seg1b = dy > 0 ? ty > ey_b : ty < ey_b
      seg2b = dx > 0 ? ex_b > sx : ex_b < sx
      if seg1b && seg2b
        from_s = dy > 0 ? Side::Bottom : Side::Top
        to_s   = dx > 0 ? Side::Left   : Side::Right
        return {from_s, to_s}
      end
    end

    # Fallback: derive sides from centre-to-centre border exit points
    src_c = R::Vector2.new(x: sx, y: sy)
    tgt_c = R::Vector2.new(x: tx, y: ty)
    a = border_exit_point(src, src_c, tgt_c)
    b = border_exit_point(tgt, tgt_c, src_c)
    {point_side(a, src), point_side(b, tgt)}
  end

  # Returns a fraction in [0, 1] representing where along *side* of element
  # *el_id* this arrow should exit/enter so that sibling arrows on the same
  # side are spread evenly and ordered to minimise crossings.
  #
  # *as_from* = true  → el_id is this arrow's source (exit side).
  # *as_from* = false → el_id is this arrow's target (entry side).
  #
  # Siblings are ordered by the centre of their *other* endpoint along the
  # perpendicular axis of the shared side:
  #   Left/Right sides → sort by other-endpoint centre y  (varies along y)
  #   Top/Bottom sides → sort by other-endpoint centre x  (varies along x)
  # This keeps the relative order of exit/entry points consistent with the
  # relative order of the elements they connect to, eliminating most crossings.
  # Ties are broken by arrow UUID for a stable, deterministic result.
  # A single arrow on a side gets fraction 0.5 (= centre), same as before.
  private def side_fraction(el_id : UUID, as_from : Bool,
                             side : Side, el_bounds : R::Rectangle) : Float32
    # Accumulate {arrow, sort_key} pairs.
    siblings = [] of {ArrowElement, Float32}

    @elements.each do |e|
      next unless e.is_a?(ArrowElement)
      a = e.as(ArrowElement)
      # Keep only arrows that use el_id on the same end (from or to).
      sibling_end_id = as_from ? a.from_id : a.to_id
      next unless sibling_end_id == el_id

      # Resolve both endpoints so we can call natural_sides.
      sib_from_el = @elements.find { |x| x.id == a.from_id }
      sib_to_el   = @elements.find { |x| x.id == a.to_id }
      next unless sib_from_el && sib_to_el

      sib_src = sib_from_el.bounds
      sib_tgt = sib_to_el.bounds
      sib_dx  = (sib_tgt.x + sib_tgt.width  / 2.0_f32) - (sib_src.x + sib_src.width  / 2.0_f32)
      sib_dy  = (sib_tgt.y + sib_tgt.height / 2.0_f32) - (sib_src.y + sib_src.height / 2.0_f32)

      sib_from_side, sib_to_side = natural_sides(sib_src, sib_tgt, sib_dx, sib_dy)
      sib_side = as_from ? sib_from_side : sib_to_side
      next unless sib_side == side

      # Sort key: centre of the OTHER endpoint along the side's perpendicular axis.
      # Ascending order maps smaller perpendicular coordinate → smaller fraction
      # (higher/lefter exit point), keeping arrow order consistent with target layout.
      other_b  = as_from ? sib_tgt : sib_src
      sort_key = case side
                 when Side::Left, Side::Right  then other_b.y + other_b.height / 2.0_f32
                 when Side::Top,  Side::Bottom then other_b.x + other_b.width  / 2.0_f32
                 else                               other_b.y + other_b.height / 2.0_f32
                 end

      siblings << {a, sort_key}
    end

    sorted  = siblings.sort_by { |(a, key)| {key, a.id.to_s} }
    my_rank = sorted.index { |(a, _)| a.id == self.id } || 0
    (my_rank + 1).to_f32 / (sorted.size + 1).to_f32
  end

  # Returns the world-space point on *side* of rectangle *b* at position
  # *frac* (0 = start of side, 1 = end of side, 0.5 = centre).
  private def exit_point_on_side(side : Side, b : R::Rectangle, frac : Float32) : R::Vector2
    case side
    when Side::Left   then R::Vector2.new(x: b.x,           y: b.y + frac * b.height)
    when Side::Right  then R::Vector2.new(x: b.x + b.width, y: b.y + frac * b.height)
    when Side::Top    then R::Vector2.new(x: b.x + frac * b.width, y: b.y)
    when Side::Bottom then R::Vector2.new(x: b.x + frac * b.width, y: b.y + b.height)
    else                   R::Vector2.new(x: b.x + b.width / 2.0_f32, y: b.y + b.height / 2.0_f32)
    end
  end

  # Which border of *b* is *pt* closest to?
  private enum Side; Left; Right; Top; Bottom; end

  private def point_side(pt : R::Vector2, b : R::Rectangle) : Side
    dl = (pt.x - b.x).abs
    dr = (pt.x - (b.x + b.width)).abs
    dt = (pt.y - b.y).abs
    db = (pt.y - (b.y + b.height)).abs
    case [dl, dr, dt, db].min
    when dl then Side::Left
    when dr then Side::Right
    when dt then Side::Top
    else         Side::Bottom
    end
  end

  # Returns the point where the ray from *origin* toward *toward* exits *b*.
  private def border_exit_point(b : R::Rectangle, origin : R::Vector2, toward : R::Vector2) : R::Vector2
    dx = toward.x - origin.x
    dy = toward.y - origin.y
    return origin if dx.abs < 0.001_f32 && dy.abs < 0.001_f32
    t_min = Float32::MAX
    if dx > 0.001_f32
      t = (b.x + b.width - origin.x) / dx
      y = origin.y + t * dy
      t_min = t if t >= 0 && y >= b.y && y <= b.y + b.height && t < t_min
    end
    if dx < -0.001_f32
      t = (b.x - origin.x) / dx
      y = origin.y + t * dy
      t_min = t if t >= 0 && y >= b.y && y <= b.y + b.height && t < t_min
    end
    if dy > 0.001_f32
      t = (b.y + b.height - origin.y) / dy
      x = origin.x + t * dx
      t_min = t if t >= 0 && x >= b.x && x <= b.x + b.width && t < t_min
    end
    if dy < -0.001_f32
      t = (b.y - origin.y) / dy
      x = origin.x + t * dx
      t_min = t if t >= 0 && x >= b.x && x <= b.x + b.width && t < t_min
    end
    t_min < Float32::MAX ? R::Vector2.new(x: origin.x + t_min * dx, y: origin.y + t_min * dy) : origin
  end

  # ── Drawing helpers ──────────────────────────────────────────────────────────

  # Draws the polyline *pts* as shaft segments plus a filled arrowhead at the end.
  private def draw_segments(pts : Array(R::Vector2), color : R::Color, width : Float32)
    return if pts.size < 2
    last  = pts.last
    prev  = pts[pts.size - 2]
    adx   = last.x - prev.x
    ady   = last.y - prev.y
    len   = Math.sqrt(adx * adx + ady * ady).to_f32
    return if len < 1.0_f32
    ux = adx / len
    uy = ady / len
    shaft_tip = R::Vector2.new(x: last.x - ux * ARROWHEAD_LEN, y: last.y - uy * ARROWHEAD_LEN)

    # All segments up to (but not reaching) the arrowhead base.
    (pts.size - 2).times { |i| R.draw_line_ex(pts[i], pts[i + 1], width, color) }
    R.draw_line_ex(prev, shaft_tip, width, color)

    # Filled arrowhead triangle.
    px   = -uy
    py   =  ux
    tip  = last
    left  = R::Vector2.new(x: shaft_tip.x + px * ARROWHEAD_HALF, y: shaft_tip.y + py * ARROWHEAD_HALF)
    right = R::Vector2.new(x: shaft_tip.x - px * ARROWHEAD_HALF, y: shaft_tip.y - py * ARROWHEAD_HALF)
    R.draw_triangle(tip, right, left, color)
  end

  private def update_bounds_from_points(pts : Array(R::Vector2))
    return if pts.empty?
    min_x = pts.min_of(&.x)
    min_y = pts.min_of(&.y)
    max_x = pts.max_of(&.x)
    max_y = pts.max_of(&.y)
    @bounds = R::Rectangle.new(x: min_x, y: min_y,
                                width: [max_x - min_x, 1.0_f32].max,
                                height: [max_y - min_y, 1.0_f32].max)
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
    Math.sqrt((p.x - (a.x + t * dx))**2 + (p.y - (a.y + t * dy))**2).to_f32
  end
end
