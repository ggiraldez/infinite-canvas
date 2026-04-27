class IdleMode < InputMode
  def initialize(@cursor_tool : Canvas::CursorTool); end

  def cursor_tool : Canvas::CursorTool?
    @cursor_tool
  end

  def on_mouse_press(canvas : Canvas, mouse_world : R::Vector2,
                     mouse_screen : R::Vector2, is_double_click : Bool) : InputMode
    shift = R.key_down?(R::KeyboardKey::LeftShift) || R.key_down?(R::KeyboardKey::RightShift)
    case @cursor_tool
    when Canvas::CursorTool::Selection
      handle_selection_press(canvas, mouse_world, shift, is_double_click)
    when Canvas::CursorTool::Arrow
      canvas.cleanup_empty_text_selection
      canvas.select_element(nil)
      if (idx = canvas.hit_test_element(mouse_world)) && !canvas.elements[idx].is_a?(ArrowElement)
        src = canvas.elements[idx]
        cx = src.bounds.x + src.bounds.width / 2.0_f32
        cy = src.bounds.y + src.bounds.height / 2.0_f32
        ConnectingArrowMode.new(idx, R::Vector2.new(x: cx, y: cy), mouse_world, @cursor_tool)
      else
        self
      end
    else # Rect or Text
      canvas.cleanup_empty_text_selection
      canvas.select_element(nil)
      DrawingShapeMode.new(mouse_world, @cursor_tool)
    end
  end

  def on_mouse_drag(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    self
  end

  def on_mouse_release(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    self
  end

  def on_escape(canvas : Canvas) : InputMode
    if canvas.selected_indices.size > 1
      canvas.clear_multi_selection
    elsif canvas.selected_index
      canvas.cleanup_empty_text_selection
      canvas.select_element(nil)
    end
    self
  end

  private def handle_selection_press(canvas : Canvas, mouse_world : R::Vector2,
                                     shift : Bool, is_double_click : Bool) : InputMode
    if (handle = canvas.hit_test_handles(mouse_world))
      idx = canvas.selected_index.not_nil!
      canvas.commit_text_session_if_active
      ResizingElementMode.new(handle, mouse_world, canvas.elements[idx].bounds, @cursor_tool)
    elsif (idx = canvas.hit_test_element(mouse_world))
      was_editing_clicked = canvas.text_session_id == canvas.elements[idx].id

      if shift && !was_editing_clicked && !canvas.elements[idx].is_a?(ArrowElement)
        removed_at = canvas.cleanup_empty_text_selection
        idx -= 1 if removed_at && idx > removed_at
        canvas.toggle_element_in_selection(idx)
        IdleMode.new(@cursor_tool)
      elsif canvas.in_multi_selection?(idx)
        canvas.commit_text_session_if_active
        multi_starts = canvas.selected_indices.map { |i| canvas.elements[i].bounds }
        MovingElementsMode.new(mouse_world, nil, multi_starts, @cursor_tool)
      else
        removed_at = canvas.cleanup_empty_text_selection
        if removed_at == idx
          IdleMode.new(@cursor_tool)
        else
          idx -= 1 if removed_at && idx > removed_at
          el = canvas.elements[idx]
          already_sel = canvas.selected_index == idx
          was_editing = canvas.text_session_id == el.id
          canvas.commit_text_session_if_active if already_sel
          canvas.select_element(idx)

          pending_enter_edit = case el
                               when TextElement
                                 !was_editing || shift ||
                                   (mouse_world.x >= el.bounds.x + TextElement::PADDING &&
                                     mouse_world.x <= el.bounds.x + el.bounds.width - TextElement::PADDING &&
                                     mouse_world.y >= el.bounds.y + TextElement::PADDING &&
                                     mouse_world.y <= el.bounds.y + el.bounds.height - TextElement::PADDING)
                               when RectElement
                                 if was_editing
                                   canvas.hit_test_rect_label(el, mouse_world) || shift
                                 else
                                   already_sel || canvas.hit_test_rect_label(el, mouse_world)
                                 end
                               else
                                 false
                               end

          double_click_done_at_press = false
          if is_double_click && was_editing && pending_enter_edit
            canvas.text_session_id = el.id
            case el
            when TextElement
              el.place_cursor_at_world_pos(mouse_world, extend_selection: shift && was_editing)
              el.select_word_at_cursor(extend_sel: shift && was_editing)
            when RectElement
              el.place_cursor_at_world_pos(mouse_world, extend_selection: shift && was_editing)
              el.select_word_at_cursor(extend_sel: shift && was_editing)
            end
            double_click_done_at_press = true
          end

          PressingOnElementMode.new(
            press_pos: mouse_world,
            element_idx: idx,
            drag_start_bounds: el.bounds,
            pending_enter_edit: pending_enter_edit,
            pending_shift_click: shift && was_editing,
            pending_double_click: is_double_click,
            press_was_editing: was_editing,
            double_click_done_at_press: double_click_done_at_press,
            previous_cursor_tool: @cursor_tool
          )
        end
      end
    else
      canvas.cleanup_empty_text_selection
      canvas.select_element(nil)
      RubberBandSelectMode.new(mouse_world)
    end
  end
end
