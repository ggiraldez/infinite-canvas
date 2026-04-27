class ResizingElementMode < InputMode
  def initialize(
    @active_handle : Canvas::Handle,
    @drag_start_mouse : R::Vector2,
    @drag_start_bounds : R::Rectangle,
    @previous_cursor_tool : Canvas::CursorTool,
  ); end

  def on_mouse_press(canvas : Canvas, mouse_world : R::Vector2,
                     mouse_screen : R::Vector2, is_double_click : Bool) : InputMode
    IdleMode.new(@previous_cursor_tool)
  end

  def on_mouse_drag(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    return self unless (idx = canvas.selected_index)
    el = canvas.elements[idx]
    min_w, min_h = el.min_size
    shift = R.key_down?(R::KeyboardKey::LeftShift) || R.key_down?(R::KeyboardKey::RightShift)
    target = shift ? R::Vector2.new(x: canvas.snap_to_grid(mouse_world.x),
      y: canvas.snap_to_grid(mouse_world.y)) : mouse_world
    el.bounds = canvas.apply_resize(@active_handle, @drag_start_bounds, @drag_start_mouse, target, min_w, min_h)
    if el.is_a?(TextElement)
      el.fixed_width = true
      canvas.refresh_element_layout(el)
    end
    canvas.refresh_drag_preview([el.id])
    self
  end

  def on_mouse_release(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    canvas.commit_text_session_if_active
    if (idx = canvas.selected_index)
      el = canvas.elements[idx]
      b = el.bounds
      sb = @drag_start_bounds
      if b.x != sb.x || b.y != sb.y || b.width != sb.width || b.height != sb.height
        canvas.emit(ResizeElementEvent.new(el.id, BoundsData.new(b.x, b.y, b.width, b.height)))
      end
    end
    IdleMode.new(@previous_cursor_tool)
  end

  def on_escape(canvas : Canvas) : InputMode
    if (idx = canvas.selected_index)
      canvas.elements[idx].bounds = @drag_start_bounds
    end
    canvas.cleanup_empty_text_selection
    canvas.select_element(nil)
    IdleMode.new(@previous_cursor_tool)
  end
end
