class TextEditingMode < InputMode
  def initialize(@session_element_id : UUID, @previous_cursor_tool : Canvas::CursorTool); end

  def accepts_text_input? : Bool
    true
  end

  def cursor_tool : Canvas::CursorTool?
    @previous_cursor_tool
  end

  def on_mouse_press(canvas : Canvas, mouse_world : R::Vector2,
                     mouse_screen : R::Vector2, is_double_click : Bool) : InputMode
    # Don't commit upfront — select_element and the explicit already_sel commit
    # in IdleMode will handle it correctly (was_editing must be computed before commit).
    IdleMode.new(@previous_cursor_tool)
      .on_mouse_press(canvas, mouse_world, mouse_screen, is_double_click)
  end

  def on_mouse_drag(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    self
  end

  def on_mouse_release(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    self
  end

  def on_escape(canvas : Canvas) : InputMode
    canvas.commit_text_session_if_active
    canvas.cleanup_empty_text_selection
    canvas.select_element(nil)
    IdleMode.new(@previous_cursor_tool)
  end

  def deactivate(canvas : Canvas) : Nil
    canvas.commit_text_session_if_active
  end
end
