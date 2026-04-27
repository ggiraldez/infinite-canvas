require "./model"

# Pure geometric helpers for arrow routing — no Raylib dependency.
# Uses BoundsData for rectangles and {Float32, Float32} pairs for points.
# Mirrors the logic in arrow_layout.cr but operates on plain Crystal types
# so LayoutEngine can call it from unit tests without a Raylib dependency.
module ArrowGeometry
  enum Side
    Left; Right; Top; Bottom
  end

  alias Pt = {Float32, Float32}

  # Which border sides the arrow will use for *src* (exit) and *tgt* (entry)
  # given the centre-to-centre displacement (*dx*, *dy*).
  def self.natural_sides(src : BoundsData, tgt : BoundsData,
                         dx : Float32, dy : Float32) : {Side, Side}
    sx = src.x + src.w / 2.0_f32
    sy = src.y + src.h / 2.0_f32
    tx = tgt.x + tgt.w / 2.0_f32
    ty = tgt.y + tgt.h / 2.0_f32

    if dx.abs > 0.5_f32 && dy.abs > 0.5_f32
      # Option A: horizontal exit from src, vertical entry to tgt.
      ex_a = dx > 0 ? src.x + src.w : src.x
      ey_a = dy > 0 ? tgt.y : tgt.y + tgt.h
      seg1a = dx > 0 ? tx > ex_a : tx < ex_a
      seg2a = dy > 0 ? ey_a > sy : ey_a < sy
      if seg1a && seg2a
        from_s = dx > 0 ? Side::Right : Side::Left
        to_s = dy > 0 ? Side::Top : Side::Bottom
        return {from_s, to_s}
      end

      # Option B: vertical exit from src, horizontal entry to tgt.
      ey_b = dy > 0 ? src.y + src.h : src.y
      ex_b = dx > 0 ? tgt.x : tgt.x + tgt.w
      seg1b = dy > 0 ? ty > ey_b : ty < ey_b
      seg2b = dx > 0 ? ex_b > sx : ex_b < sx
      if seg1b && seg2b
        from_s = dy > 0 ? Side::Bottom : Side::Top
        to_s = dx > 0 ? Side::Left : Side::Right
        return {from_s, to_s}
      end
    end

    # Fallback: derive sides from centre-to-centre border exit points.
    a = border_exit_point(src, sx, sy, tx, ty)
    b = border_exit_point(tgt, tx, ty, sx, sy)
    {point_side(a, src), point_side(b, tgt)}
  end

  # World-space point on *side* of *b* at position *frac* (0 = start, 1 = end).
  def self.exit_point_on_side(side : Side, b : BoundsData, frac : Float32) : Pt
    case side
    when Side::Left   then {b.x, b.y + frac * b.h}
    when Side::Right  then {b.x + b.w, b.y + frac * b.h}
    when Side::Top    then {b.x + frac * b.w, b.y}
    when Side::Bottom then {b.x + frac * b.w, b.y + b.h}
    else                   {b.x + b.w / 2.0_f32, b.y + b.h / 2.0_f32}
    end
  end

  # Which border of *b* is *pt* closest to?
  def self.point_side(pt : Pt, b : BoundsData) : Side
    px, py = pt
    dl = (px - b.x).abs
    dr = (px - (b.x + b.w)).abs
    dt = (py - b.y).abs
    db = (py - (b.y + b.h)).abs
    min = dl
    s = Side::Left
    if dr < min
      min = dr; s = Side::Right
    end
    if dt < min
      min = dt; s = Side::Top
    end
    if db < min
      s = Side::Bottom
    end
    s
  end

  # Point where the ray from *(ox, oy)* toward *(tx, ty)* exits rectangle *b*.
  def self.border_exit_point(b : BoundsData,
                             ox : Float32, oy : Float32,
                             tx : Float32, ty : Float32) : Pt
    ddx = tx - ox
    ddy = ty - oy
    return {ox, oy} if ddx.abs < 0.001_f32 && ddy.abs < 0.001_f32
    t_min = Float32::MAX
    if ddx > 0.001_f32
      t = (b.x + b.w - ox) / ddx
      y = oy + t * ddy
      t_min = t if t >= 0 && y >= b.y && y <= b.y + b.h && t < t_min
    end
    if ddx < -0.001_f32
      t = (b.x - ox) / ddx
      y = oy + t * ddy
      t_min = t if t >= 0 && y >= b.y && y <= b.y + b.h && t < t_min
    end
    if ddy > 0.001_f32
      t = (b.y + b.h - oy) / ddy
      x = ox + t * ddx
      t_min = t if t >= 0 && x >= b.x && x <= b.x + b.w && t < t_min
    end
    if ddy < -0.001_f32
      t = (b.y - oy) / ddy
      x = ox + t * ddx
      t_min = t if t >= 0 && x >= b.x && x <= b.x + b.w && t < t_min
    end
    t_min < Float32::MAX ? {ox + t_min * ddx, oy + t_min * ddy} : {ox, oy}
  end

  # Two border points on the centre-to-centre line (straight routing).
  def self.straight_route(src : BoundsData, tgt : BoundsData) : Array(Pt)
    src_cx = src.x + src.w / 2.0_f32
    src_cy = src.y + src.h / 2.0_f32
    tgt_cx = tgt.x + tgt.w / 2.0_f32
    tgt_cy = tgt.y + tgt.h / 2.0_f32
    [border_exit_point(src, src_cx, src_cy, tgt_cx, tgt_cy),
     border_exit_point(tgt, tgt_cx, tgt_cy, src_cx, src_cy)]
  end

  # Ordered waypoints for an orthogonal (rectilinear) path.
  # Caller supplies the pre-computed *from_side* / *to_side* and spread fractions
  # so this function is pure geometry with no model lookups.
  def self.ortho_route(src : BoundsData, tgt : BoundsData,
                       frac_src : Float32, frac_tgt : Float32,
                       from_side : Side, to_side : Side) : Array(Pt)
    sx = src.x + src.w / 2.0_f32
    sy = src.y + src.h / 2.0_f32
    tx = tgt.x + tgt.w / 2.0_f32
    ty = tgt.y + tgt.h / 2.0_f32
    dx = tx - sx
    dy = ty - sy

    exit_y = src.y + frac_src * src.h
    exit_x = src.x + frac_src * src.w
    entry_x = tgt.x + frac_tgt * tgt.w
    entry_y = tgt.y + frac_tgt * tgt.h

    # ── L-shape attempts (2 segments) ────────────────────────────────────────
    if dx.abs > 0.5_f32 && dy.abs > 0.5_f32
      ex_a = dx > 0 ? src.x + src.w : src.x
      ey_a = dy > 0 ? tgt.y : tgt.y + tgt.h
      seg1a = dx > 0 ? entry_x > ex_a : entry_x < ex_a
      seg2a = dy > 0 ? ey_a > exit_y : ey_a < exit_y
      if seg1a && seg2a
        return [{ex_a, exit_y}, {entry_x, exit_y}, {entry_x, ey_a}]
      end

      ey_b = dy > 0 ? src.y + src.h : src.y
      ex_b = dx > 0 ? tgt.x : tgt.x + tgt.w
      seg1b = dy > 0 ? entry_y > ey_b : entry_y < ey_b
      seg2b = dx > 0 ? ex_b > exit_x : ex_b < exit_x
      if seg1b && seg2b
        return [{exit_x, ey_b}, {exit_x, entry_y}, {ex_b, entry_y}]
      end
    end

    # ── 3-segment fallback ────────────────────────────────────────────────────
    a = exit_point_on_side(from_side, src, frac_src)
    b = exit_point_on_side(to_side, tgt, frac_tgt)
    ax, ay = a
    bx, by = b

    case {from_side, to_side}
    when {Side::Right, Side::Left}, {Side::Left, Side::Right}
      mid_x = (ax + bx) / 2.0_f32
      [a, {mid_x, ay}, {mid_x, by}, b]
    when {Side::Top, Side::Bottom}, {Side::Bottom, Side::Top}
      mid_y = (ay + by) / 2.0_f32
      [a, {ax, mid_y}, {bx, mid_y}, b]
    when {Side::Right, Side::Right}
      ext = (ax > bx ? ax : bx) + 30.0_f32
      [a, {ext, ay}, {ext, by}, b]
    when {Side::Left, Side::Left}
      ext = (ax < bx ? ax : bx) - 30.0_f32
      [a, {ext, ay}, {ext, by}, b]
    when {Side::Bottom, Side::Bottom}
      ext = (ay > by ? ay : by) + 30.0_f32
      [a, {ax, ext}, {bx, ext}, b]
    when {Side::Top, Side::Top}
      ext = (ay < by ? ay : by) - 30.0_f32
      [a, {ax, ext}, {bx, ext}, b]
    else
      [a, {bx, ay}, b]
    end
  end
end
