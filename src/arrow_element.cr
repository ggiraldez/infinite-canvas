require "./arrow_layout"

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
    pts = compute_path
    return false unless pts
    (pts.size - 1).times.any? { |i| segment_dist(world_point, pts[i], pts[i + 1]) <= threshold }
  end

  # Resolves endpoints, computes the route, updates bounds, and returns the path.
  # Returns nil when either endpoint element cannot be found.
  # Non-private so Renderer can call it for drawing.
  def compute_path : Array(R::Vector2)?
    from_el = resolve_from
    to_el   = resolve_to
    return nil unless from_el && to_el
    pts = route(from_el.bounds, to_el.bounds)
    update_bounds_from_points(pts)
    pts
  end

  private def resolve_from : Element?
    @elements.find { |e| e.id == @from_id }
  end

  private def resolve_to : Element?
    @elements.find { |e| e.id == @to_id }
  end

  # Side is owned by ArrowLayout; alias for brevity in the methods below.
  private alias Side = ArrowLayout::Side

  # ── Routing ──────────────────────────────────────────────────────────────────

  private def route(src : R::Rectangle, tgt : R::Rectangle) : Array(R::Vector2)
    @routing_style.straight? ? ArrowLayout.straight_route(src, tgt) : ortho_route(src, tgt)
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

    from_side, to_side = ArrowLayout.natural_sides(src, tgt, dx, dy)
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
    a = ArrowLayout.exit_point_on_side(from_side, src, frac_src)
    b = ArrowLayout.exit_point_on_side(to_side,   tgt, frac_tgt)

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

      sib_from_side, sib_to_side = ArrowLayout.natural_sides(sib_src, sib_tgt, sib_dx, sib_dy)
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
