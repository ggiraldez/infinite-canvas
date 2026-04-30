require "./model"
require "./render_data"
require "./text_layout"
require "./arrow_geometry"

# Computes render-ready layout data from the canvas model using an injected
# measurer, so the layout pass has no Raylib dependency and can be unit-tested.
class LayoutEngine
  # Mirror element constants to avoid a Raylib dependency here.
  TEXT_FONT_SIZE  = 20
  TEXT_PADDING    =  8
  LABEL_FONT_SIZE = 20
  LABEL_PAD_H     = 16

  def initialize(@measure : Measurer, @spacing : Int32 = 0)
  end

  # Public entry point for laying out a single TextModel — used by Canvas
  # to refresh the live element cache during text sessions without a full sync.
  def layout_text_element(m : TextModel) : TextRenderData
    layout_text(m)
  end

  def layout(model : CanvasModel) : RenderData
    rd = RenderData.new
    model.elements.each do |m|
      rd[m.id] = case m
                 when TextModel  then layout_text(m)
                 when RectModel  then layout_rect(m)
                 when ArrowModel then layout_arrow(model, m)
                 else                 raise "unknown element type: #{m.class}"
                 end
    end
    rd
  end

  # Re-layout a single arrow using live element bounds from *overrides* in place of
  # model bounds. Used for per-frame drag preview without mutating the model.
  def layout_arrow_preview(model : CanvasModel, m : ArrowModel,
                           overrides : Hash(UUID, BoundsData)) : ArrowRenderData
    layout_arrow(model, m, overrides)
  end

  private def layout_text(m : TextModel) : TextRenderData
    font_size = TEXT_FONT_SIZE
    padding = TEXT_PADDING

    if m.fixed_width
      avail_w = (m.bounds.w - padding * 2).to_f32
      line_runs = measure_line_runs(m.text, avail_w)
      line_count = m.text.empty? ? 1 : line_runs.size
      mh = (line_count * font_size + padding * 2).to_f32
      return TextRenderData.new(
        BoundsData.new(m.bounds.x, m.bounds.y, m.bounds.w, mh),
        line_runs, true)
    end

    if m.text.empty?
      cursor_w = @measure.call("|")
      content_w = (cursor_w + padding * 2).to_f32
      content_h = (font_size + padding * 2).to_f32
      return TextRenderData.new(
        BoundsData.new(m.bounds.x, m.bounds.y, content_w, content_h),
        [{"", 0}] of {String, Int32}, false)
    end

    lines = m.text.split('\n')
    max_tw = lines.map { |l| @measure.call(l) }.max? || 0
    content_w = (max_tw + padding * 2).to_f32
    content_h = (lines.size * font_size + padding * 2).to_f32

    cap = m.max_auto_width
    if cap && content_w > cap
      avail_w = (cap - padding * 2).to_f32
      line_runs = measure_line_runs(m.text, avail_w)
      line_count = line_runs.size
      mh = (line_count * font_size + padding * 2).to_f32
      TextRenderData.new(
        BoundsData.new(m.bounds.x, m.bounds.y, cap, mh),
        line_runs, true)
    else
      avail_w = (content_w - padding * 2).to_f32
      line_runs = measure_line_runs(m.text, avail_w)
      TextRenderData.new(
        BoundsData.new(m.bounds.x, m.bounds.y, content_w, content_h),
        line_runs, false)
    end
  end

  private def layout_rect(m : RectModel) : RectRenderData
    font_size = LABEL_FONT_SIZE
    label_lines = m.label.split('\n').map { |line| {line, @measure.call(line)} }
    RectRenderData.new(m.bounds, label_lines)
  end

  private def layout_arrow(model : CanvasModel, m : ArrowModel,
                           overrides : Hash(UUID, BoundsData) = {} of UUID => BoundsData) : ArrowRenderData
    from_m = model.find_by_id(m.from_id)
    to_m = model.find_by_id(m.to_id)

    unless from_m && to_m
      return ArrowRenderData.new([] of {Float32, Float32}, m.bounds)
    end

    src = overrides[m.from_id]? || from_m.bounds
    tgt = overrides[m.to_id]? || to_m.bounds

    waypoints = if m.routing_style == "straight"
                  ArrowGeometry.straight_route(src, tgt)
                else
                  sx = src.x + src.w / 2.0_f32
                  sy = src.y + src.h / 2.0_f32
                  tx = tgt.x + tgt.w / 2.0_f32
                  ty = tgt.y + tgt.h / 2.0_f32
                  dx = tx - sx
                  dy = ty - sy

                  from_side, to_side = ArrowGeometry.natural_sides(src, tgt, dx, dy)
                  frac_src = arrow_side_fraction(model, m, m.from_id, true, from_side, src, overrides)
                  frac_tgt = arrow_side_fraction(model, m, m.to_id, false, to_side, tgt, overrides)
                  ArrowGeometry.ortho_route(src, tgt, frac_src, frac_tgt, from_side, to_side)
                end

    return ArrowRenderData.new(waypoints, m.bounds) if waypoints.empty?

    min_x = waypoints.min_of { |p| p[0] }
    min_y = waypoints.min_of { |p| p[1] }
    max_x = waypoints.max_of { |p| p[0] }
    max_y = waypoints.max_of { |p| p[1] }
    bw = max_x - min_x
    bh = max_y - min_y
    bounds = BoundsData.new(min_x, min_y,
      bw > 0 ? bw : 1.0_f32,
      bh > 0 ? bh : 1.0_f32)
    ArrowRenderData.new(waypoints, bounds)
  end

  # Returns the fraction [0,1] along *side* of element *el_id* where *arrow*
  # should exit/enter, spread evenly among sibling arrows on the same side.
  # Siblings are sorted by the centre of their *other* endpoint along the
  # perpendicular axis so that exit-point order tracks connection order.
  private def arrow_side_fraction(model : CanvasModel, arrow : ArrowModel,
                                  el_id : UUID, as_from : Bool,
                                  side : ArrowGeometry::Side,
                                  el_bounds : BoundsData,
                                  overrides : Hash(UUID, BoundsData) = {} of UUID => BoundsData) : Float32
    siblings = [] of {UUID, Float32}

    model.elements.each do |e|
      next unless e.is_a?(ArrowModel)
      a = e.as(ArrowModel)
      next unless (as_from ? a.from_id : a.to_id) == el_id

      sib_from_m = model.find_by_id(a.from_id)
      sib_to_m = model.find_by_id(a.to_id)
      next unless sib_from_m && sib_to_m

      sib_src = overrides[a.from_id]? || sib_from_m.bounds
      sib_tgt = overrides[a.to_id]? || sib_to_m.bounds
      sib_dx = (sib_tgt.x + sib_tgt.w / 2.0_f32) - (sib_src.x + sib_src.w / 2.0_f32)
      sib_dy = (sib_tgt.y + sib_tgt.h / 2.0_f32) - (sib_src.y + sib_src.h / 2.0_f32)

      sib_from_side, sib_to_side = ArrowGeometry.natural_sides(sib_src, sib_tgt, sib_dx, sib_dy)
      sib_side = as_from ? sib_from_side : sib_to_side
      next unless sib_side == side

      other_b = as_from ? sib_tgt : sib_src
      sort_key = case side
                 when ArrowGeometry::Side::Left, ArrowGeometry::Side::Right
                   other_b.y + other_b.h / 2.0_f32
                 when ArrowGeometry::Side::Top, ArrowGeometry::Side::Bottom
                   other_b.x + other_b.w / 2.0_f32
                 else
                   other_b.y + other_b.h / 2.0_f32
                 end

      siblings << {a.id, sort_key}
    end

    sorted = siblings.sort_by { |(id, key)| {key, id.to_s} }
    my_rank = sorted.index { |(id, _)| id == arrow.id } || 0
    (my_rank + 1).to_f32 / (sorted.size + 1).to_f32
  end

  private def measure_line_runs(text : String, avail_w : Float32) : TextLayoutData
    TextLayout.compute(text, avail_w, @spacing) { |s| @measure.call(s) }
  end
end
