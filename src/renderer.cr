# ─── Renderer ─────────────────────────────────────────────────────────────────

# Pure presentation layer: reads element data and draws to screen.
# No mutation of element state — only reading properties and calling Raylib.
class Renderer
  # Draw an element's body (no cursor, no selection overlay).
  def draw_element(el : Element) : Nil
    case el
    when RectElement  then draw_rect(el)
    when TextElement  then draw_text(el)
    when ArrowElement then draw_arrow(el)
    end
  end

  # Draw the arrow highlighted in *color* at *width* — used for selection overlay.
  def draw_arrow_highlighted(el : ArrowElement, color : R::Color, width : Float32) : Nil
    pts = el.compute_path
    return unless pts
    draw_segments(pts, color, width)
  end

  # Draw the blinking text cursor (and selection highlight) for a selected element.
  def draw_cursor(el : Element) : Nil
    case el
    when RectElement then draw_rect_cursor(el)
    when TextElement then draw_text_cursor(el)
    end
  end

  # ── Private drawing ──────────────────────────────────────────────────────────

  private def draw_rect(el : RectElement)
    R.draw_rectangle_rec(el.bounds, el.fill)
    R.draw_rectangle_lines_ex(el.bounds, el.stroke_width, el.stroke)
    draw_rect_label(el)
  end

  private def draw_rect_label(el : RectElement)
    return if el.label.empty?
    lines        = el.label.split('\n')
    total_height = lines.size * RectElement::LABEL_FONT_SIZE
    start_y      = el.bounds.y + (el.bounds.height - total_height) / 2.0_f32
    lines.each_with_index do |line, i|
      tw = R.measure_text(line, RectElement::LABEL_FONT_SIZE)
      lx = (el.bounds.x + (el.bounds.width - tw) / 2.0_f32).to_i
      ly = (start_y + i * RectElement::LABEL_FONT_SIZE).to_i
      R.draw_text(line, lx, ly, RectElement::LABEL_FONT_SIZE, RectElement::LABEL_COLOR)
    end
  end

  private def draw_rect_cursor(el : RectElement)
    all_lines = el.label.split('\n')
    total_h   = all_lines.size * RectElement::LABEL_FONT_SIZE

    if (range = el.selection_range)
      el.selection_line_ranges(range[0], range[1]).each do |line_idx, col_start, col_end|
        line    = all_lines.fetch(line_idx, "")
        chars   = line.chars
        full_tw = R.measure_text(line, RectElement::LABEL_FONT_SIZE)
        line_x  = el.bounds.x + (el.bounds.width - full_tw) / 2.0_f32
        x1 = line_x + R.measure_text(chars[0, col_start].join, RectElement::LABEL_FONT_SIZE)
        x2 = line_x + R.measure_text(chars[0, col_end].join, RectElement::LABEL_FONT_SIZE)
        y  = el.bounds.y + (el.bounds.height - total_h) / 2.0_f32 + line_idx * RectElement::LABEL_FONT_SIZE
        R.draw_rectangle_rec(
          R::Rectangle.new(x: x1, y: y, width: x2 - x1, height: RectElement::LABEL_FONT_SIZE.to_f32),
          RectElement::SELECTION_COLOR)
      end
    end

    return unless el.cursor_visible?
    lines_b  = el.lines_before_cursor
    line_idx = lines_b.size - 1
    col_text = lines_b.last
    cur_line = all_lines.fetch(line_idx, "")
    full_tw  = R.measure_text(cur_line, RectElement::LABEL_FONT_SIZE)
    col_tw   = R.measure_text(col_text, RectElement::LABEL_FONT_SIZE)
    cx = (el.bounds.x + (el.bounds.width - full_tw) / 2.0_f32 + col_tw).to_i
    cy = (el.bounds.y + (el.bounds.height - total_h) / 2.0_f32 + line_idx * RectElement::LABEL_FONT_SIZE).to_i
    R.draw_text("|", cx, cy, RectElement::LABEL_FONT_SIZE, RectElement::LABEL_COLOR)
  end

  private def draw_text(el : TextElement)
    return if el.text.empty?
    if el.wraps?
      el.visual_line_runs.each_with_index do |(line, _), i|
        R.draw_text(line,
          el.bounds.x.to_i + TextElement::PADDING,
          (el.bounds.y + TextElement::PADDING + i * TextElement::FONT_SIZE).to_i,
          TextElement::FONT_SIZE, TextElement::TEXT_COLOR)
      end
    else
      el.text.split('\n').each_with_index do |line, i|
        R.draw_text(line,
          el.bounds.x.to_i + TextElement::PADDING,
          (el.bounds.y + TextElement::PADDING + i * TextElement::FONT_SIZE).to_i,
          TextElement::FONT_SIZE, TextElement::TEXT_COLOR)
      end
    end
  end

  private def draw_text_cursor(el : TextElement)
    if el.wraps?
      draw_text_cursor_wrapped(el)
    else
      draw_text_cursor_raw(el)
    end
  end

  private def draw_text_cursor_raw(el : TextElement)
    if (range = el.selection_range)
      all_lines = el.text.split('\n')
      el.selection_line_ranges(range[0], range[1]).each do |line_idx, col_start, col_end|
        line  = all_lines.fetch(line_idx, "")
        chars = line.chars
        x1 = el.bounds.x + TextElement::PADDING + R.measure_text(chars[0, col_start].join, TextElement::FONT_SIZE)
        x2 = el.bounds.x + TextElement::PADDING + R.measure_text(chars[0, col_end].join, TextElement::FONT_SIZE)
        y  = el.bounds.y + TextElement::PADDING + line_idx * TextElement::FONT_SIZE
        R.draw_rectangle_rec(
          R::Rectangle.new(x: x1, y: y, width: x2 - x1, height: TextElement::FONT_SIZE.to_f32),
          TextElement::SELECTION_COLOR)
      end
    end

    return unless el.cursor_visible?
    lines_b  = el.lines_before_cursor
    line_idx = lines_b.size - 1
    col_text = lines_b.last
    tw = R.measure_text(col_text, TextElement::FONT_SIZE)
    cx = el.bounds.x.to_i + TextElement::PADDING + tw
    cy = (el.bounds.y + TextElement::PADDING + line_idx * TextElement::FONT_SIZE).to_i
    R.draw_text("|", cx, cy, TextElement::FONT_SIZE, TextElement::TEXT_COLOR)
  end

  private def draw_text_cursor_wrapped(el : TextElement)
    if (range = el.selection_range)
      all_runs = el.visual_line_runs
      el.visual_selection_ranges(range[0], range[1]).each do |vi, col_start, col_end|
        line_str = all_runs.fetch(vi, {"", 0})[0]
        chars    = line_str.chars
        x1 = el.bounds.x + TextElement::PADDING + R.measure_text(chars[0, col_start].join, TextElement::FONT_SIZE)
        x2 = el.bounds.x + TextElement::PADDING + R.measure_text(chars[0, col_end].join, TextElement::FONT_SIZE)
        y  = el.bounds.y + TextElement::PADDING + vi * TextElement::FONT_SIZE
        R.draw_rectangle_rec(
          R::Rectangle.new(x: x1, y: y, width: x2 - x1, height: TextElement::FONT_SIZE.to_f32),
          TextElement::SELECTION_COLOR)
      end
    end

    return unless el.cursor_visible?
    vi, x_px = el.cursor_visual_pos
    cx = (el.bounds.x + TextElement::PADDING + x_px).to_i
    cy = (el.bounds.y + TextElement::PADDING + vi * TextElement::FONT_SIZE).to_i
    R.draw_text("|", cx, cy, TextElement::FONT_SIZE, TextElement::TEXT_COLOR)
  end

  private def draw_arrow(el : ArrowElement)
    pts = el.compute_path
    return unless pts
    draw_segments(pts, ArrowElement::ARROW_COLOR, ArrowElement::ARROW_WIDTH)
  end

  # Draws a polyline as shaft segments plus a filled arrowhead at the tip.
  private def draw_segments(pts : Array(R::Vector2), color : R::Color, width : Float32)
    return if pts.size < 2
    last = pts.last
    prev = pts[pts.size - 2]
    adx  = last.x - prev.x
    ady  = last.y - prev.y
    len  = Math.sqrt(adx * adx + ady * ady).to_f32
    return if len < 1.0_f32
    ux = adx / len
    uy = ady / len
    shaft_tip = R::Vector2.new(
      x: last.x - ux * ArrowElement::ARROWHEAD_LEN,
      y: last.y - uy * ArrowElement::ARROWHEAD_LEN)

    (pts.size - 2).times { |i| R.draw_line_ex(pts[i], pts[i + 1], width, color) }
    R.draw_line_ex(prev, shaft_tip, width, color)

    px    = -uy
    py    =  ux
    tip   = last
    left  = R::Vector2.new(x: shaft_tip.x + px * ArrowElement::ARROWHEAD_HALF,
                            y: shaft_tip.y + py * ArrowElement::ARROWHEAD_HALF)
    right = R::Vector2.new(x: shaft_tip.x - px * ArrowElement::ARROWHEAD_HALF,
                            y: shaft_tip.y - py * ArrowElement::ARROWHEAD_HALF)
    R.draw_triangle(tip, right, left, color)
  end
end
