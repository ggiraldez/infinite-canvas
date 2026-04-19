require "./model"
require "./render_data"
require "./text_layout"

# Computes render-ready layout data from the canvas model using an injected
# measurer, so the layout pass has no Raylib dependency and can be unit-tested.
class LayoutEngine
  # Mirror element constants to avoid a Raylib dependency here.
  TEXT_FONT_SIZE  = 20
  TEXT_PADDING    =  8
  LABEL_FONT_SIZE = 20
  LABEL_PAD_H     = 16

  def initialize(@measure : Measurer)
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

  private def layout_text(m : TextModel) : TextRenderData
    font_size = TEXT_FONT_SIZE
    padding   = TEXT_PADDING

    if m.fixed_width
      avail_w    = (m.bounds.w - padding * 2).to_f32
      line_runs  = measure_line_runs(m.text, avail_w, font_size)
      line_count = m.text.empty? ? 1 : line_runs.size
      mh         = (line_count * font_size + padding * 2).to_f32
      return TextRenderData.new(
        BoundsData.new(m.bounds.x, m.bounds.y, m.bounds.w, mh),
        line_runs, true)
    end

    if m.text.empty?
      cursor_w  = @measure.call("|", font_size)
      content_w = (cursor_w + padding * 2).to_f32
      content_h = (font_size + padding * 2).to_f32
      return TextRenderData.new(
        BoundsData.new(m.bounds.x, m.bounds.y, content_w, content_h),
        [{"", 0}] of {String, Int32}, false)
    end

    lines     = m.text.split('\n')
    max_tw    = lines.map { |l| @measure.call(l, font_size) }.max? || 0
    content_w = (max_tw + padding * 2).to_f32
    content_h = (lines.size * font_size + padding * 2).to_f32

    cap = m.max_auto_width
    if cap && content_w > cap
      avail_w    = (cap - padding * 2).to_f32
      line_runs  = measure_line_runs(m.text, avail_w, font_size)
      line_count = line_runs.size
      mh         = (line_count * font_size + padding * 2).to_f32
      TextRenderData.new(
        BoundsData.new(m.bounds.x, m.bounds.y, cap, mh),
        line_runs, true)
    else
      avail_w   = (content_w - padding * 2).to_f32
      line_runs = measure_line_runs(m.text, avail_w, font_size)
      TextRenderData.new(
        BoundsData.new(m.bounds.x, m.bounds.y, content_w, content_h),
        line_runs, false)
    end
  end

  private def layout_rect(m : RectModel) : RectRenderData
    font_size   = LABEL_FONT_SIZE
    label_lines = m.label.split('\n').map { |line| {line, @measure.call(line, font_size)} }
    RectRenderData.new(m.bounds, label_lines)
  end

  # Phase 1 stub: centre-to-centre waypoints derived from BoundsData only.
  # Full orthogonal routing moves here in Phase 2.
  private def layout_arrow(model : CanvasModel, m : ArrowModel) : ArrowRenderData
    from_m = model.find_by_id(m.from_id)
    to_m   = model.find_by_id(m.to_id)

    unless from_m && to_m
      return ArrowRenderData.new([] of {Float32, Float32}, m.bounds)
    end

    fx = from_m.bounds.x + from_m.bounds.w / 2.0_f32
    fy = from_m.bounds.y + from_m.bounds.h / 2.0_f32
    tx = to_m.bounds.x   + to_m.bounds.w   / 2.0_f32
    ty = to_m.bounds.y   + to_m.bounds.h   / 2.0_f32

    min_x  = fx < tx ? fx : tx
    min_y  = fy < ty ? fy : ty
    raw_bw = (tx - fx).abs
    raw_bh = (ty - fy).abs
    bw     = (raw_bw > 1.0_f32 ? raw_bw : 1.0_f32).to_f32
    bh     = (raw_bh > 1.0_f32 ? raw_bh : 1.0_f32).to_f32
    bounds = BoundsData.new(min_x, min_y, bw, bh)
    ArrowRenderData.new([{fx, fy}, {tx, ty}], bounds)
  end

  private def measure_line_runs(text : String, avail_w : Float32, font_size : Int32) : TextLayoutData
    TextLayout.compute(text, avail_w, font_size) { |s| @measure.call(s, font_size) }
  end
end
