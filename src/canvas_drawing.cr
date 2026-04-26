class Canvas
  private def draw_draft
    if (line = @mode.draft_arrow_line)
      R.draw_line_ex(line[0], line[1], 2.0_f32 / @camera.zoom, DRAFT_STROKE)
    elsif @mode.rubber_band_select?
      if (pair = @mode.draft_rect)
        rect = rect_from_points(pair[0], pair[1])
        R.draw_rectangle_rec(rect, SEL_DRAG_FILL)
        R.draw_rectangle_lines_ex(rect, 1.5_f32 / @camera.zoom, SEL_COLOR)
      end
    elsif (pair = @mode.draft_rect)
      rect = rect_from_points(pair[0], pair[1])
      R.draw_rectangle_rec(rect, DRAFT_FILL)
      R.draw_rectangle_lines_ex(rect, 2.0_f32 / @camera.zoom, DRAFT_STROKE)
    end
  end

  # Returns a rectangle expanded outward by *px* screen pixels, so the
  # selection ring sits on the canvas background rather than on the element fill.
  private def selection_rect(b : R::Rectangle, px : Float32 = 3.0_f32) : R::Rectangle
    exp = px / @camera.zoom
    R::Rectangle.new(x: b.x - exp, y: b.y - exp,
                     width: b.width + exp * 2, height: b.height + exp * 2)
  end

  private def draw_selection
    # Multi-selection: outlines only, no handles or cursor.
    if @selected_indices.size > 1
      thickness = 2.5_f32 / @camera.zoom
      @selected_indices.each do |idx|
        next unless idx < @elements.size
        el = @elements[idx]
        R.draw_rectangle_lines_ex(selection_rect(el.bounds), thickness, SEL_COLOR)
      end
      return
    end

    return unless (idx = @selected_index) && idx < @elements.size
    el = @elements[idx]
    thickness = 2.5_f32 / @camera.zoom

    if el.is_a?(ArrowElement)
      rd = @render_data[el.id]?
      if rd.is_a?(ArrowRenderData)
        @renderer.draw_arrow_highlighted(rd, SEL_COLOR, 4.0_f32 / @camera.zoom)
      end
      return
    end

    bounds = el.bounds
    R.draw_rectangle_lines_ex(selection_rect(bounds), thickness, SEL_COLOR)

    # Draw resize handles as small squares — only for resizable elements.
    # Width-only elements (TextElement) show just the left and right edge handles.
    if el.resizable?
      half = (HANDLE_SIZE / 2.0_f32) / @camera.zoom
      hs = HANDLE_SIZE / @camera.zoom
      handles = el.resizable_width_only? ?
        handle_positions(bounds).select { |(h, _)| h.e? || h.w? } :
        handle_positions(bounds)
      handles.each do |(_, center)|
        hr = R::Rectangle.new(x: center.x - half, y: center.y - half, width: hs, height: hs)
        R.draw_rectangle_rec(hr, R::WHITE)
        R.draw_rectangle_lines_ex(hr, 1.5_f32 / @camera.zoom, SEL_COLOR)
      end
    end

    # Blinking text cursor — only shown in text editing mode.
    rd = @render_data[el.id]?
    @renderer.draw_cursor(el, rd) if rd && @text_session_id
  end

  private def draw_grid
    screen_w = R.get_screen_width.to_f32
    screen_h = R.get_screen_height.to_f32
    top_left = R.get_screen_to_world_2d(R::Vector2.new(x: 0.0_f32, y: 0.0_f32), @camera)
    bottom_right = R.get_screen_to_world_2d(R::Vector2.new(x: screen_w, y: screen_h), @camera)

    thickness = 1.0_f32 / @camera.zoom

    start_x = (top_left.x / GRID_SPACING).floor * GRID_SPACING
    x = start_x
    while x <= bottom_right.x
      color = ((x / GRID_SPACING).round.to_i % 5 == 0) ? GRID_COLOR_MAJOR : GRID_COLOR_MINOR
      R.draw_line_ex(
        R::Vector2.new(x: x, y: top_left.y),
        R::Vector2.new(x: x, y: bottom_right.y),
        thickness, color,
      )
      x += GRID_SPACING
    end

    start_y = (top_left.y / GRID_SPACING).floor * GRID_SPACING
    y = start_y
    while y <= bottom_right.y
      color = ((y / GRID_SPACING).round.to_i % 5 == 0) ? GRID_COLOR_MAJOR : GRID_COLOR_MINOR
      R.draw_line_ex(
        R::Vector2.new(x: top_left.x, y: y),
        R::Vector2.new(x: bottom_right.x, y: y),
        thickness, color,
      )
      y += GRID_SPACING
    end

    axis = R::Color.new(r: 180, g: 180, b: 180, a: 255)
    R.draw_line_ex(
      R::Vector2.new(x: -10.0_f32, y: 0.0_f32),
      R::Vector2.new(x: 10.0_f32, y: 0.0_f32),
      thickness, axis,
    )
    R.draw_line_ex(
      R::Vector2.new(x: 0.0_f32, y: -10.0_f32),
      R::Vector2.new(x: 0.0_f32, y: 10.0_f32),
      thickness, axis,
    )
  end
end
