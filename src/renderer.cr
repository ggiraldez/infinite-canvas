# ─── Renderer ─────────────────────────────────────────────────────────────────
require "./font"

# Pure presentation layer: reads element data + pre-computed RenderData and
# draws to screen. No R.measure_text calls for layout — only for cursor/selection
# sub-line pixel offsets that require knowing a partial-prefix width.
class Renderer
  def initialize(@font : Font)
  end
  # Draw an element's body (no cursor, no selection overlay).
  def draw_element(el : Element, rd : ElementRenderData) : Nil
    case el
    when RectElement  then draw_rect(el, rd.as(RectRenderData))
    when TextElement  then draw_text(el, rd.as(TextRenderData))
    when ArrowElement then draw_arrow(rd.as(ArrowRenderData))
    end
  end

  # Draw the arrow highlighted in *color* at *width* — used for selection overlay.
  def draw_arrow_highlighted(rd : ArrowRenderData, color : R::Color, width : Float32) : Nil
    return if rd.waypoints.empty?
    pts = rd.waypoints.map { |p| R::Vector2.new(x: p[0], y: p[1]) }
    draw_segments(pts, color, width)
  end

  # Draw the blinking text cursor (and selection highlight) for a selected element.
  def draw_cursor(el : Element, rd : ElementRenderData) : Nil
    case el
    when RectElement then draw_rect_cursor(el, rd.as(RectRenderData))
    when TextElement then draw_text_cursor(el, rd.as(TextRenderData))
    end
  end

  # ── Private drawing ──────────────────────────────────────────────────────────

  private def draw_rect(el : RectElement, rd : RectRenderData)
    R.draw_rectangle_rec(el.bounds, el.fill)
    R.draw_rectangle_lines_ex(el.bounds, el.stroke_width, el.stroke)
    draw_rect_label(el, rd)
  end

  private def draw_rect_label(el : RectElement, rd : RectRenderData)
    return if rd.label_lines.all? { |(line, _)| line.empty? }
    total_height = rd.label_lines.size * RectElement::LABEL_FONT_SIZE
    start_y = el.bounds.y + (el.bounds.height - total_height) / 2.0_f32
    rd.label_lines.each_with_index do |(line, tw), i|
      lx = (el.bounds.x + (el.bounds.width - tw) / 2.0_f32).to_i
      ly = (start_y + i * RectElement::LABEL_FONT_SIZE).to_i
      @font.draw(line, lx, ly, RectElement::LABEL_FONT_SIZE, el.label_color)
    end
  end

  private def draw_rect_cursor(el : RectElement, rd : RectRenderData)
    all_lines = rd.label_lines
    total_h = all_lines.size * RectElement::LABEL_FONT_SIZE

    if (range = el.selection_range)
      el.selection_line_ranges(range[0], range[1]).each do |line_idx, col_start, col_end|
        line, full_tw = all_lines.fetch(line_idx, {"", 0})
        chars = line.chars
        line_x = el.bounds.x + (el.bounds.width - full_tw) / 2.0_f32
        x1 = line_x + @font.measure(chars[0, col_start].join, RectElement::LABEL_FONT_SIZE)
        x2 = line_x + @font.measure(chars[0, col_end].join, RectElement::LABEL_FONT_SIZE)
        y = el.bounds.y + (el.bounds.height - total_h) / 2.0_f32 + line_idx * RectElement::LABEL_FONT_SIZE
        R.draw_rectangle_rec(
          R::Rectangle.new(x: x1, y: y, width: x2 - x1, height: RectElement::LABEL_FONT_SIZE.to_f32),
          RectElement::SELECTION_COLOR)
      end
    end

    return unless el.cursor_visible?
    lines_b = el.lines_before_cursor
    line_idx = lines_b.size - 1
    col_text = lines_b.last
    _, full_tw = all_lines.fetch(line_idx, {"", 0})
    col_tw = @font.measure(col_text, RectElement::LABEL_FONT_SIZE)
    cx = (el.bounds.x + (el.bounds.width - full_tw) / 2.0_f32 + col_tw).to_i
    cy = (el.bounds.y + (el.bounds.height - total_h) / 2.0_f32 + line_idx * RectElement::LABEL_FONT_SIZE).to_i
    @font.draw("|", cx, cy, RectElement::LABEL_FONT_SIZE, el.label_color)
  end

  private def draw_text(el : TextElement, rd : TextRenderData)
    return if el.text.empty?
    rd.line_runs.each_with_index do |(line, _), i|
      @font.draw(line,
        el.bounds.x.to_i + TextElement::PADDING,
        (el.bounds.y + TextElement::PADDING + i * TextElement::FONT_SIZE).to_i,
        TextElement::FONT_SIZE, TextElement::TEXT_COLOR)
    end
  end

  private def draw_text_cursor(el : TextElement, rd : TextRenderData)
    if rd.wraps
      draw_text_cursor_wrapped(el, rd)
    else
      draw_text_cursor_raw(el, rd)
    end
  end

  private def draw_text_cursor_raw(el : TextElement, rd : TextRenderData)
    if (range = el.selection_range)
      rd.line_runs.each_with_index do |(line_str, _), line_idx|
        chars = line_str.chars
        el.selection_line_ranges(range[0], range[1]).each do |sel_line, col_start, col_end|
          next unless sel_line == line_idx
          x1 = el.bounds.x + TextElement::PADDING + @font.measure(chars[0, col_start].join, TextElement::FONT_SIZE)
          x2 = el.bounds.x + TextElement::PADDING + @font.measure(chars[0, col_end].join, TextElement::FONT_SIZE)
          y = el.bounds.y + TextElement::PADDING + line_idx * TextElement::FONT_SIZE
          R.draw_rectangle_rec(
            R::Rectangle.new(x: x1, y: y, width: x2 - x1, height: TextElement::FONT_SIZE.to_f32),
            TextElement::SELECTION_COLOR)
        end
      end
    end

    return unless el.cursor_visible?
    lines_b = el.lines_before_cursor
    line_idx = lines_b.size - 1
    col_text = lines_b.last
    tw = @font.measure(col_text, TextElement::FONT_SIZE)
    cx = el.bounds.x.to_i + TextElement::PADDING + tw
    cy = (el.bounds.y + TextElement::PADDING + line_idx * TextElement::FONT_SIZE).to_i
    @font.draw("|", cx, cy, TextElement::FONT_SIZE, TextElement::TEXT_COLOR)
  end

  private def draw_text_cursor_wrapped(el : TextElement, rd : TextRenderData)
    if (range = el.selection_range)
      text_selection_ranges(range[0], range[1], rd.line_runs).each do |vi, col_start, col_end|
        line_str = rd.line_runs.fetch(vi, {"", 0})[0]
        chars = line_str.chars
        x1 = el.bounds.x + TextElement::PADDING + @font.measure(chars[0, col_start].join, TextElement::FONT_SIZE)
        x2 = el.bounds.x + TextElement::PADDING + @font.measure(chars[0, col_end].join, TextElement::FONT_SIZE)
        y = el.bounds.y + TextElement::PADDING + vi * TextElement::FONT_SIZE
        R.draw_rectangle_rec(
          R::Rectangle.new(x: x1, y: y, width: x2 - x1, height: TextElement::FONT_SIZE.to_f32),
          TextElement::SELECTION_COLOR)
      end
    end

    return unless el.cursor_visible?
    vi, x_px = text_cursor_visual_pos(el.cursor_pos, rd.line_runs, TextElement::FONT_SIZE)
    cx = (el.bounds.x + TextElement::PADDING + x_px).to_i
    cy = (el.bounds.y + TextElement::PADDING + vi * TextElement::FONT_SIZE).to_i
    @font.draw("|", cx, cy, TextElement::FONT_SIZE, TextElement::TEXT_COLOR)
  end

  private def draw_arrow(rd : ArrowRenderData)
    return if rd.waypoints.empty?
    pts = rd.waypoints.map { |p| R::Vector2.new(x: p[0], y: p[1]) }
    draw_segments(pts, ArrowElement::ARROW_COLOR, ArrowElement::ARROW_WIDTH)
  end

  # Maps cursor_pos (char offset) to {visual_line_index, x_pixel_offset}.
  private def text_cursor_visual_pos(cursor_pos : Int32, line_runs : TextLayoutData, font_size : Int32) : {Int32, Int32}
    return {0, 0} if line_runs.empty?
    line_runs.each_with_index do |(line_str, line_start), vi|
      next_start = vi + 1 < line_runs.size ? line_runs[vi + 1][1] : Int32::MAX
      if cursor_pos >= line_start && cursor_pos < next_start
        col = [cursor_pos - line_start, line_str.chars.size].min
        x_px = @font.measure(line_str.chars[0...col].join, font_size)
        return {vi, x_px}
      end
    end
    last_line = line_runs.last[0]
    {line_runs.size - 1, @font.measure(last_line, font_size)}
  end

  # Returns {vi, col_start, col_end} for each visual line overlapping [sel_start, sel_end).
  private def text_selection_ranges(sel_start : Int32, sel_end : Int32, line_runs : TextLayoutData) : Array({Int32, Int32, Int32})
    result = [] of {Int32, Int32, Int32}
    line_runs.each_with_index do |(line_str, line_start), vi|
      line_chars = line_str.chars.size
      line_end = line_start + line_chars
      if sel_start <= line_end && sel_end > line_start
        col_start = [sel_start - line_start, 0].max
        col_end = [sel_end - line_start, line_chars].min
        result << {vi, col_start, col_end}
      end
    end
    result
  end

  # Draws a polyline as shaft segments plus a filled arrowhead at the tip.
  private def draw_segments(pts : Array(R::Vector2), color : R::Color, width : Float32)
    return if pts.size < 2
    last = pts.last
    prev = pts[pts.size - 2]
    adx = last.x - prev.x
    ady = last.y - prev.y
    len = Math.sqrt(adx * adx + ady * ady).to_f32
    return if len < 1.0_f32
    ux = adx / len
    uy = ady / len
    shaft_tip = R::Vector2.new(
      x: last.x - ux * ArrowElement::ARROWHEAD_LEN,
      y: last.y - uy * ArrowElement::ARROWHEAD_LEN)

    (pts.size - 2).times { |i| R.draw_line_ex(pts[i], pts[i + 1], width, color) }
    R.draw_line_ex(prev, shaft_tip, width, color)

    px = -uy
    py = ux
    tip = last
    left = R::Vector2.new(x: shaft_tip.x + px * ArrowElement::ARROWHEAD_HALF,
      y: shaft_tip.y + py * ArrowElement::ARROWHEAD_HALF)
    right = R::Vector2.new(x: shaft_tip.x - px * ArrowElement::ARROWHEAD_HALF,
      y: shaft_tip.y - py * ArrowElement::ARROWHEAD_HALF)
    R.draw_triangle(tip, right, left, color)
  end
end
