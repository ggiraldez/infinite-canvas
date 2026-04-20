require "./arrow_layout"

# ─── Arrow ────────────────────────────────────────────────────────────────────

# A directional arrow connecting two other elements by their UUIDs.
# All routing is owned by LayoutEngine; waypoints are injected via
# cached_waypoints after each layout pass and read by the Renderer.
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

  # Arrows are not hit-tested via bounding-rect containment.
  # Canvas performs line-proximity testing directly using render data.
  def contains?(world_point : R::Vector2) : Bool
    false
  end
end
