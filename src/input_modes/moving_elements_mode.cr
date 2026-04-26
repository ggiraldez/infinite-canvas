class MovingElementsMode < InputMode
  # multi_drag_starts is set for multi-element moves; drag_start_bounds for single.
  def initialize(
    @drag_start_mouse : R::Vector2,
    @drag_start_bounds : R::Rectangle?,
    @multi_drag_starts : Array(R::Rectangle)?,
    @previous_cursor_tool : Canvas::CursorTool
  ); end

  def on_mouse_press(canvas : Canvas, mouse_world : R::Vector2,
                     mouse_screen : R::Vector2, is_double_click : Bool) : InputMode
    IdleMode.new(@previous_cursor_tool)
  end

  def on_mouse_drag(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    shift = R.key_down?(R::KeyboardKey::LeftShift) || R.key_down?(R::KeyboardKey::RightShift)

    if (starts = @multi_drag_starts)
      sm = @drag_start_mouse
      dx = mouse_world.x - sm.x
      dy = mouse_world.y - sm.y
      if shift && !starts.empty?
        anchor = starts[0]
        dx = canvas.snap_to_grid(anchor.x + dx) - anchor.x
        dy = canvas.snap_to_grid(anchor.y + dy) - anchor.y
      end
      canvas.selected_indices.each_with_index do |el_idx, i|
        sb = starts[i]
        canvas.elements[el_idx].bounds = R::Rectangle.new(
          x: sb.x + dx, y: sb.y + dy,
          width: sb.width, height: sb.height
        )
      end
      canvas.refresh_drag_preview(canvas.selected_ids)
    elsif (sb = @drag_start_bounds) && (idx = canvas.selected_index)
      sm = @drag_start_mouse
      dx = mouse_world.x - sm.x
      dy = mouse_world.y - sm.y
      new_x = shift ? canvas.snap_to_grid(sb.x + dx) : sb.x + dx
      new_y = shift ? canvas.snap_to_grid(sb.y + dy) : sb.y + dy
      canvas.elements[idx].bounds = R::Rectangle.new(
        x: new_x, y: new_y,
        width: sb.width, height: sb.height
      )
      canvas.refresh_drag_preview([canvas.elements[idx].id])
    end
    self
  end

  def on_mouse_release(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    canvas.commit_text_session_if_active
    if (starts = @multi_drag_starts) && canvas.selected_indices.size > 1
      moves = canvas.selected_indices.map do |i|
        el = canvas.elements[i]
        b  = el.bounds
        {el.id, BoundsData.new(b.x, b.y, b.width, b.height)}
      end
      moved = canvas.selected_indices.each_with_index.any? do |el_idx, i|
        b  = canvas.elements[el_idx].bounds
        sb = starts[i]
        b.x != sb.x || b.y != sb.y
      end
      canvas.emit(MoveMultiEvent.new(moves)) if moved
    elsif (idx = canvas.selected_index)
      el = canvas.elements[idx]
      b  = el.bounds
      if (sb = @drag_start_bounds).nil? || b.x != sb.x || b.y != sb.y
        canvas.emit(MoveElementEvent.new(el.id, BoundsData.new(b.x, b.y, b.width, b.height)))
      end
    end
    IdleMode.new(@previous_cursor_tool)
  end

  def on_escape(canvas : Canvas) : InputMode
    if (starts = @multi_drag_starts)
      canvas.selected_indices.each_with_index do |el_idx, i|
        canvas.elements[el_idx].bounds = starts[i]
      end
    elsif (sb = @drag_start_bounds) && (idx = canvas.selected_index)
      canvas.elements[idx].bounds = sb
    end
    canvas.cleanup_empty_text_selection
    canvas.select_element(nil)
    IdleMode.new(@previous_cursor_tool)
  end
end
