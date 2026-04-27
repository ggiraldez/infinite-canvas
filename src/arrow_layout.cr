require "raylib-cr"

# Waypoints for a routed arrow path.
alias ArrowLayoutData = Array(R::Vector2)

# Pure geometric helpers for arrow routing.
# High-level routing (ortho_route, side_fraction) lives in ArrowElement for now
# because it needs the canvas element list; it will move here in Phase 6 once
# that dependency is replaced by the model layer.
module ArrowLayout
  # Border side of a rectangle.
  enum Side
    Left; Right; Top; Bottom
  end

  # Predicts which border sides the arrow will use for *src* (exit) and *tgt*
  # (entry) given the centre-to-centre displacement (*dx*, *dy*).
  # Mirrors the Option A / Option B / fallback decision tree in ortho_route.
  def self.natural_sides(src : R::Rectangle, tgt : R::Rectangle,
                         dx : Float32, dy : Float32) : {Side, Side}
    sx = src.x + src.width / 2.0_f32
    sy = src.y + src.height / 2.0_f32
    tx = tgt.x + tgt.width / 2.0_f32
    ty = tgt.y + tgt.height / 2.0_f32

    if dx.abs > 0.5_f32 && dy.abs > 0.5_f32
      # Option A: horizontal exit from src, vertical entry to tgt.
      ex_a = dx > 0 ? src.x + src.width : src.x
      ey_a = dy > 0 ? tgt.y : tgt.y + tgt.height
      seg1a = dx > 0 ? tx > ex_a : tx < ex_a
      seg2a = dy > 0 ? ey_a > sy : ey_a < sy
      if seg1a && seg2a
        from_s = dx > 0 ? Side::Right : Side::Left
        to_s = dy > 0 ? Side::Top : Side::Bottom
        return {from_s, to_s}
      end

      # Option B: vertical exit from src, horizontal entry to tgt.
      ey_b = dy > 0 ? src.y + src.height : src.y
      ex_b = dx > 0 ? tgt.x : tgt.x + tgt.width
      seg1b = dy > 0 ? ty > ey_b : ty < ey_b
      seg2b = dx > 0 ? ex_b > sx : ex_b < sx
      if seg1b && seg2b
        from_s = dy > 0 ? Side::Bottom : Side::Top
        to_s = dx > 0 ? Side::Left : Side::Right
        return {from_s, to_s}
      end
    end

    # Fallback: derive sides from centre-to-centre border exit points.
    src_c = R::Vector2.new(x: sx, y: sy)
    tgt_c = R::Vector2.new(x: tx, y: ty)
    a = self.border_exit_point(src, src_c, tgt_c)
    b = self.border_exit_point(tgt, tgt_c, src_c)
    {self.point_side(a, src), self.point_side(b, tgt)}
  end

  # World-space point on *side* of *b* at position *frac* (0=start, 1=end).
  def self.exit_point_on_side(side : Side, b : R::Rectangle, frac : Float32) : R::Vector2
    case side
    when Side::Left   then R::Vector2.new(x: b.x, y: b.y + frac * b.height)
    when Side::Right  then R::Vector2.new(x: b.x + b.width, y: b.y + frac * b.height)
    when Side::Top    then R::Vector2.new(x: b.x + frac * b.width, y: b.y)
    when Side::Bottom then R::Vector2.new(x: b.x + frac * b.width, y: b.y + b.height)
    else                   R::Vector2.new(x: b.x + b.width / 2.0_f32, y: b.y + b.height / 2.0_f32)
    end
  end

  # Which border of *b* is *pt* closest to?
  def self.point_side(pt : R::Vector2, b : R::Rectangle) : Side
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

  # Point where the ray from *origin* toward *toward* exits rectangle *b*.
  def self.border_exit_point(b : R::Rectangle, origin : R::Vector2, toward : R::Vector2) : R::Vector2
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

  # Two border points on the centre-to-centre line (straight routing).
  def self.straight_route(src : R::Rectangle, tgt : R::Rectangle) : ArrowLayoutData
    src_c = R::Vector2.new(x: src.x + src.width / 2.0_f32, y: src.y + src.height / 2.0_f32)
    tgt_c = R::Vector2.new(x: tgt.x + tgt.width / 2.0_f32, y: tgt.y + tgt.height / 2.0_f32)
    [self.border_exit_point(src, src_c, tgt_c), self.border_exit_point(tgt, tgt_c, src_c)]
  end
end
