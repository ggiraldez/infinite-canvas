class TextSelectingMode < InputMode
  def initialize(
    @element_idx : Int32,
    @session_element_id : UUID,
    @word_start : Int32?,
    @word_end : Int32?,
    @previous_cursor_tool : Canvas::CursorTool,
  ); end

  def text_selecting? : Bool
    true
  end

  def on_mouse_press(canvas : Canvas, mouse_world : R::Vector2,
                     mouse_screen : R::Vector2, is_double_click : Bool) : InputMode
    canvas.commit_text_session_if_active
    IdleMode.new(@previous_cursor_tool)
      .on_mouse_press(canvas, mouse_world, mouse_screen, is_double_click)
  end

  def on_mouse_drag(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    return self unless canvas.text_session_id
    el = canvas.elements[@element_idx]
    case el
    when TextElement, RectElement
      ws = @word_start
      we = @word_end
      if ws && we
        target = el.char_pos_at_world(mouse_world)
        if target <= ws
          el.set_selection(anchor: we, cursor: target)
        elsif target >= we
          el.set_selection(anchor: ws, cursor: target)
        else
          el.set_selection(anchor: ws, cursor: we)
        end
      else
        el.place_cursor_at_world_pos(mouse_world, extend_selection: true)
      end
      canvas.refresh_element_layout(el)
    end
    self
  end

  def on_mouse_release(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    TextEditingMode.new(@session_element_id, @previous_cursor_tool)
  end

  def on_escape(canvas : Canvas) : InputMode
    canvas.commit_text_session_if_active
    canvas.cleanup_empty_text_selection
    canvas.select_element(nil)
    IdleMode.new(@previous_cursor_tool)
  end
end
