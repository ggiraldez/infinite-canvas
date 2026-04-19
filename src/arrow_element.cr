require "./arrow_layout"

# ─── Arrow ────────────────────────────────────────────────────────────────────

# A directional arrow connecting two other elements by their UUIDs.
# Waypoints are pre-computed by LayoutEngine and injected via cached_waypoints
# after each layout pass, so compute_path is a simple cache read.
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

  # Pre-computed by LayoutEngine and injected by Canvas after each layout pass.
  property cached_waypoints : Array(R::Vector2)? = nil

  def initialize(@from_id : UUID, @to_id : UUID,
                 @routing_style : RoutingStyle = RoutingStyle::Orthogonal,
                 id : UUID = UUID.random)
    super(R::Rectangle.new(x: 0.0_f32, y: 0.0_f32, width: 0.0_f32, height: 0.0_f32), id)
  end

  def resizable? : Bool
    false
  end

  # Arrows are not hit-tested via the normal bounding-rect check.
  def contains?(world_point : R::Vector2) : Bool
    false
  end

  # Returns true when *world_point* is within *threshold* world units of any
  # segment of the arrow.
  def near_line?(world_point : R::Vector2, threshold : Float32) : Bool
    pts = compute_path
    return false unless pts
    (pts.size - 1).times.any? { |i| segment_dist(world_point, pts[i], pts[i + 1]) <= threshold }
  end

  # Returns the pre-computed waypoints, or nil if the layout pass has not run yet.
  def compute_path : Array(R::Vector2)?
    @cached_waypoints
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
