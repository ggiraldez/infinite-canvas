class PressingOnElementMode < InputMode
  def initialize(
    @press_pos : R::Vector2,
    @element_idx : Int32,
    @drag_start_bounds : R::Rectangle,
    @pending_enter_edit : Bool,
    @pending_shift_click : Bool,
    @pending_double_click : Bool,
    @press_was_editing : Bool,
    @double_click_done_at_press : Bool,
    @previous_cursor_tool : Canvas::CursorTool
  ); end

  def on_mouse_press(canvas : Canvas, mouse_world : R::Vector2,
                     mouse_screen : R::Vector2, is_double_click : Bool) : InputMode
    IdleMode.new(@previous_cursor_tool)
      .on_mouse_press(canvas, mouse_world, mouse_screen, is_double_click)
  end

  def on_mouse_drag(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    if @pending_enter_edit
      dx = (mouse_world.x - @press_pos.x).abs
      dy = (mouse_world.y - @press_pos.y).abs
      return self if dx <= 2.0_f32 && dy <= 2.0_f32

      # Drag threshold crossed.
      shift_at_press = @pending_shift_click
      if @press_was_editing
        el = canvas.elements[@element_idx]
        if el.is_a?(TextElement) || el.is_a?(RectElement)
          canvas.text_session_id = el.id
          word_start = nil
          word_end   = nil
          if @double_click_done_at_press
            if (range = el.selection_range)
              word_start = range[0]
              word_end   = range[1]
            end
          else
            case el
            when TextElement then el.place_cursor_at_world_pos(@press_pos, extend_selection: shift_at_press)
            when RectElement then el.place_cursor_at_world_pos(@press_pos, extend_selection: shift_at_press)
            end
          end
          return TextSelectingMode.new(@element_idx, el.id, word_start, word_end, @previous_cursor_tool)
        end
      end
      MovingElementsMode.new(@press_pos, @drag_start_bounds, nil, @previous_cursor_tool)
        .on_mouse_drag(canvas, mouse_world)
    else
      MovingElementsMode.new(@press_pos, @drag_start_bounds, nil, @previous_cursor_tool)
        .on_mouse_drag(canvas, mouse_world)
    end
  end

  def on_mouse_release(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    return IdleMode.new(@previous_cursor_tool) if @element_idx >= canvas.elements.size

    el = canvas.elements[@element_idx]
    if @pending_enter_edit && (el.is_a?(TextElement) || el.is_a?(RectElement))
      canvas.text_session_id = el.id
      unless @double_click_done_at_press
        case el
        when TextElement
          el.place_cursor_at_world_pos(@press_pos, extend_selection: @pending_shift_click)
          el.select_word_at_cursor(extend_sel: @pending_shift_click) if @pending_double_click
        when RectElement
          el.place_cursor_at_world_pos(@press_pos, extend_selection: @pending_shift_click)
          el.select_word_at_cursor(extend_sel: @pending_shift_click) if @pending_double_click
        end
      end
      TextEditingMode.new(el.id, @previous_cursor_tool)
    else
      b = el.bounds
      canvas.emit(MoveElementEvent.new(el.id, BoundsData.new(b.x, b.y, b.width, b.height)))
      IdleMode.new(@previous_cursor_tool)
    end
  end

  def on_escape(canvas : Canvas) : InputMode
    if @element_idx < canvas.elements.size
      canvas.elements[@element_idx].bounds = @drag_start_bounds
    end
    canvas.cleanup_empty_text_selection
    canvas.select_element(nil)
    IdleMode.new(@previous_cursor_tool)
  end
end
