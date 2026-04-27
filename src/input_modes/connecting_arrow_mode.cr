class ConnectingArrowMode < InputMode
  def initialize(
    @source_index : Int32,
    @draw_start : R::Vector2,
    @draw_current : R::Vector2,
    @previous_cursor_tool : Canvas::CursorTool
  ); end

  def cursor_tool : Canvas::CursorTool?
    @previous_cursor_tool
  end

  def draft_arrow_line : {R::Vector2, R::Vector2}?
    {@draw_start, @draw_current}
  end

  def on_mouse_press(canvas : Canvas, mouse_world : R::Vector2,
                     mouse_screen : R::Vector2, is_double_click : Bool) : InputMode
    IdleMode.new(@previous_cursor_tool)
  end

  def on_mouse_drag(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    @draw_current = mouse_world
    self
  end

  def on_mouse_release(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    if (tgt_idx = canvas.hit_test_element(mouse_world))
      if tgt_idx != @source_index && !canvas.elements[tgt_idx].is_a?(ArrowElement)
        from_id  = canvas.elements[@source_index].id
        to_id    = canvas.elements[tgt_idx].id
        arrow_id = UUID.random
        canvas.emit(CreateArrowEvent.new(arrow_id, from_id, to_id))
        return IdleMode.new(Canvas::CursorTool::Selection)
      end
    end
    IdleMode.new(@previous_cursor_tool)
  end

  def on_escape(canvas : Canvas) : InputMode
    IdleMode.new(@previous_cursor_tool)
  end
end
