class Canvas
  private def handle_pan
    if R.mouse_button_down?(R::MouseButton::Right) || R.mouse_button_down?(R::MouseButton::Middle)
      delta = R.get_mouse_delta
      @camera.target = R::Vector2.new(
        x: @camera.target.x - delta.x / @camera.zoom,
        y: @camera.target.y - delta.y / @camera.zoom,
      )
    end
  end

  private def handle_zoom
    wheel = R.get_mouse_wheel_move
    return if wheel == 0.0_f32

    mouse_screen = R.get_mouse_position
    world_before = R.get_screen_to_world_2d(mouse_screen, @camera)

    new_zoom = if wheel > 0
      ZOOM_LEVELS.find { |z| z > @camera.zoom } || ZOOM_LEVELS.last
    else
      ZOOM_LEVELS.reverse.find { |z| z < @camera.zoom } || ZOOM_LEVELS.first
    end
    @camera.zoom = new_zoom

    world_after = R.get_screen_to_world_2d(mouse_screen, @camera)
    @camera.target = R::Vector2.new(
      x: @camera.target.x + (world_before.x - world_after.x),
      y: @camera.target.y + (world_before.y - world_after.y),
    )
  end

  private def handle_left_mouse
    mouse_world = R.get_screen_to_world_2d(R.get_mouse_position, @camera)

    if R.mouse_button_pressed?(R::MouseButton::Left)
      if @active_tool.selection?
        # Selection tool: hit-test handles → resize, elements → move, empty → deselect.
        if (handle = hit_test_handles(mouse_world))
          idx = @selected_index.not_nil!
          @drag_mode = DragMode::Resizing
          @active_handle = handle
          @drag_start_mouse = mouse_world
          @drag_start_bounds = @elements[idx].bounds
        elsif (idx = hit_test_element(mouse_world))
          if in_multi_selection?(idx)
            # Clicked inside an existing multi-selection: begin moving all of them.
            @drag_mode = DragMode::Moving
            @drag_start_mouse = mouse_world
            @multi_drag_starts = @selected_indices.map { |i| @elements[i].bounds }
          else
            # If the clicked element was itself an empty text node, clean it up and
            # skip selection. Otherwise adjust the index if cleanup shifted things.
            removed_at = cleanup_empty_text_selection
            unless removed_at == idx
              idx -= 1 if removed_at && idx > removed_at
              select_element(idx)
              @drag_mode = DragMode::Moving
              @drag_start_mouse = mouse_world
              @drag_start_bounds = @elements[idx].bounds
            end
          end
        else
          # Empty space: clear selection and start a rubber-band drag.
          cleanup_empty_text_selection
          select_element(nil)
          @drag_mode = DragMode::Selecting
          @draw_start = mouse_world
          @draw_current = mouse_world
        end
      elsif @active_tool.arrow?
        # Arrow tool: press on a non-arrow element to begin connecting.
        cleanup_empty_text_selection
        select_element(nil)
        if (idx = hit_test_element(mouse_world)) && !@elements[idx].is_a?(ArrowElement)
          @arrow_source_index = idx
          @drag_mode = DragMode::Connecting
          src_bounds = @elements[idx].bounds
          @draw_start = R::Vector2.new(
            x: src_bounds.x + src_bounds.width / 2.0_f32,
            y: src_bounds.y + src_bounds.height / 2.0_f32,
          )
          @draw_current = mouse_world
        end
      else
        # Rect / Text tool: skip hit-testing entirely and always start drawing.
        cleanup_empty_text_selection
        select_element(nil)
        @drag_mode = DragMode::Drawing
        @draw_start = mouse_world
        @draw_current = mouse_world
      end

    elsif R.mouse_button_down?(R::MouseButton::Left)
      case @drag_mode
      when DragMode::Drawing, DragMode::Connecting, DragMode::Selecting
        @draw_current = mouse_world
      when DragMode::Moving
        shift = R.key_down?(R::KeyboardKey::LeftShift) || R.key_down?(R::KeyboardKey::RightShift)
        if (starts = @multi_drag_starts) && (sm = @drag_start_mouse)
          dx = mouse_world.x - sm.x
          dy = mouse_world.y - sm.y
          if shift && !starts.empty?
            # Snap by anchoring the first element's corner to the snap grid and
            # applying the same offset to all others, preserving relative positions.
            anchor = starts[0]
            dx = snap_to_grid(anchor.x + dx) - anchor.x
            dy = snap_to_grid(anchor.y + dy) - anchor.y
          end
          @selected_indices.each_with_index do |el_idx, i|
            sb = starts[i]
            @elements[el_idx].bounds = R::Rectangle.new(
              x: sb.x + dx, y: sb.y + dy,
              width: sb.width, height: sb.height,
            )
          end
        elsif (idx = @selected_index) && (sm = @drag_start_mouse) && (sb = @drag_start_bounds)
          dx = mouse_world.x - sm.x
          dy = mouse_world.y - sm.y
          new_x = shift ? snap_to_grid(sb.x + dx) : sb.x + dx
          new_y = shift ? snap_to_grid(sb.y + dy) : sb.y + dy
          @elements[idx].bounds = R::Rectangle.new(
            x: new_x, y: new_y,
            width: sb.width, height: sb.height,
          )
        end
      when DragMode::Resizing
        if (idx = @selected_index) && (h = @active_handle) && (sm = @drag_start_mouse) && (sb = @drag_start_bounds)
          el = @elements[idx]
          min_w, min_h = el.min_size
          shift = R.key_down?(R::KeyboardKey::LeftShift) || R.key_down?(R::KeyboardKey::RightShift)
          target = shift ? R::Vector2.new(x: snap_to_grid(mouse_world.x), y: snap_to_grid(mouse_world.y)) : mouse_world
          el.bounds = apply_resize(h, sb, sm, target, min_w, min_h)
        end
      end

    elsif R.mouse_button_released?(R::MouseButton::Left)
      if @drag_mode.selecting?
        # Finish rubber-band: select all non-arrow elements whose bounds overlap the rect.
        if (start = @draw_start) && (current = @draw_current)
          sel_rect = rect_from_points(start, current)
          indices = (0...@elements.size).select do |i|
            el = @elements[i]
            !el.is_a?(ArrowElement) && rects_overlap?(sel_rect, el.bounds)
          end.to_a
          if indices.size == 1
            select_element(indices.first)
          elsif indices.size > 1
            select_multi(indices)
          end
        end
        @draw_start = nil
        @draw_current = nil
        @drag_mode = DragMode::None
      elsif @drag_mode.connecting?
        # Create an arrow if the mouse was released over a different non-arrow element.
        if (src_idx = @arrow_source_index) && (tgt_idx = hit_test_element(mouse_world))
          if tgt_idx != src_idx && !@elements[tgt_idx].is_a?(ArrowElement)
            arrow = ArrowElement.new(@elements[src_idx].id, @elements[tgt_idx].id, @elements)
            @elements << arrow
            @active_tool = ActiveTool::Selection
          end
        end
        @arrow_source_index = nil
        @draw_start = nil
        @draw_current = nil
        @drag_mode = DragMode::None
      elsif @drag_mode.drawing?
        if (start = @draw_start) && (current = @draw_current)
          dragged = rect_from_points(start, current)
          is_drag = dragged.width >= 4.0_f32 || dragged.height >= 4.0_f32
          el = if is_drag
            case @active_tool
            when ActiveTool::Rect then RectElement.new(dragged)
            when ActiveTool::Text then TextElement.new(dragged)
            end
          else
            case @active_tool
            when ActiveTool::Rect
              RectElement.new(R::Rectangle.new(x: start.x, y: start.y,
                                               width: DEFAULT_RECT_W, height: DEFAULT_RECT_H))
            when ActiveTool::Text
              TextElement.new(R::Rectangle.new(x: start.x, y: start.y,
                                               width: 0.0_f32, height: 0.0_f32))
            end
          end
          if el
            el.fit_content
            @elements << el
            select_element(@elements.size - 1)
            @active_tool = ActiveTool::Selection
          end
        end
        @draw_start = nil
        @draw_current = nil
      end
      @drag_mode = DragMode::None
      @drag_start_mouse = nil
      @drag_start_bounds = nil
      @active_handle = nil
      @multi_drag_starts = nil
    end
  end

  private def handle_text_input
    return unless (idx = @selected_index)
    el = @elements[idx]

    # Append any queued printable characters.
    while (ch = R.get_char_pressed) > 0
      el.handle_char_input(ch.chr)
    end

    # Enter inserts a newline.
    if R.key_pressed?(R::KeyboardKey::Enter) || R.key_pressed_repeat?(R::KeyboardKey::Enter)
      el.handle_enter
    end

    # Arrow keys: move the cursor. Ctrl jumps by word; Shift extends selection.
    ctrl  = R.key_down?(R::KeyboardKey::LeftControl) || R.key_down?(R::KeyboardKey::RightControl)
    shift = R.key_down?(R::KeyboardKey::LeftShift)   || R.key_down?(R::KeyboardKey::RightShift)

    # Backspace: delete character (or word with Ctrl) before the cursor.
    if R.key_pressed?(R::KeyboardKey::Backspace) || R.key_pressed_repeat?(R::KeyboardKey::Backspace)
      ctrl ? el.handle_backspace_word : el.handle_backspace
    end

    # Clipboard: Ctrl+C copies selection, Ctrl+V pastes (replacing selection).
    if ctrl && R.key_pressed?(R::KeyboardKey::C)
      if (copied = el.handle_copy)
        R.set_clipboard_text(copied)
      end
    end
    if ctrl && (R.key_pressed?(R::KeyboardKey::V) || R.key_pressed_repeat?(R::KeyboardKey::V))
      cb = String.new(R.get_clipboard_text.as(Pointer(UInt8)))
      el.handle_paste(cb) unless cb.empty?
    end
    if R.key_pressed?(R::KeyboardKey::Left) || R.key_pressed_repeat?(R::KeyboardKey::Left)
      ctrl ? el.handle_cursor_word_left(shift) : el.handle_cursor_left(shift)
    end
    if R.key_pressed?(R::KeyboardKey::Right) || R.key_pressed_repeat?(R::KeyboardKey::Right)
      ctrl ? el.handle_cursor_word_right(shift) : el.handle_cursor_right(shift)
    end
    if R.key_pressed?(R::KeyboardKey::Up) || R.key_pressed_repeat?(R::KeyboardKey::Up)
      el.handle_cursor_up(shift)
    end
    if R.key_pressed?(R::KeyboardKey::Down) || R.key_pressed_repeat?(R::KeyboardKey::Down)
      el.handle_cursor_down(shift)
    end

    el.fit_content
  end

  private def handle_delete
    return unless R.key_pressed?(R::KeyboardKey::Delete) || R.key_pressed_repeat?(R::KeyboardKey::Delete)
    if multi_selected?
      ids = @selected_indices.map { |i| @elements[i].id }.to_set
      @elements.reject! do |e|
        ids.includes?(e.id) ||
          (e.is_a?(ArrowElement) && (ids.includes?(e.from_id) || ids.includes?(e.to_id)))
      end
      @selected_indices = [] of Int32
    elsif (idx = @selected_index)
      deleted_id = @elements[idx].id
      @elements.delete_at(idx)
      @elements.reject! { |e| e.is_a?(ArrowElement) && (e.from_id == deleted_id || e.to_id == deleted_id) }
      @selected_index = nil
    end
  end

  # Toggle the routing style of the selected arrow with Tab.
  private def handle_arrow_style_toggle
    return unless (idx = @selected_index)
    return unless R.key_pressed?(R::KeyboardKey::Tab)
    el = @elements[idx]
    return unless el.is_a?(ArrowElement)
    el.routing_style = el.routing_style.straight? ?
      ArrowElement::RoutingStyle::Orthogonal :
      ArrowElement::RoutingStyle::Straight
  end

  # Switch active tool with S / R / T / A. Guarded while an element is selected so
  # the keys remain available for text input when editing.
  private def handle_tool_switch
    return if @selected_index
    if R.key_pressed?(R::KeyboardKey::S)
      @selected_indices = [] of Int32
      @active_tool = ActiveTool::Selection
    elsif R.key_pressed?(R::KeyboardKey::R)
      @selected_indices = [] of Int32
      @active_tool = ActiveTool::Rect
    elsif R.key_pressed?(R::KeyboardKey::T)
      @selected_indices = [] of Int32
      @active_tool = ActiveTool::Text
    elsif R.key_pressed?(R::KeyboardKey::A)
      @selected_indices = [] of Int32
      @active_tool = ActiveTool::Arrow
    end
  end

  # Changes @selected_index, clearing any text selection on the element losing focus.
  # Also clears multi-selection.
  private def select_element(new_idx : Int32?)
    old_idx = @selected_index
    @selected_indices = [] of Int32
    if old_idx != new_idx
      @elements[old_idx].clear_selection if old_idx && old_idx < @elements.size
      @selected_index = new_idx
    end
  end

  # Activates multi-selection, clearing any single-selected element.
  private def select_multi(indices : Array(Int32))
    old_idx = @selected_index
    @elements[old_idx].clear_selection if old_idx && old_idx < @elements.size
    @selected_index = nil
    @selected_indices = indices
  end

  # Returns true when more than one element is selected.
  private def multi_selected? : Bool
    @selected_indices.size > 1
  end

  # Returns true if *idx* is part of the current multi-selection.
  private def in_multi_selection?(idx : Int32) : Bool
    @selected_indices.includes?(idx)
  end

  # Snaps *v* to the nearest snap-grid line.
  private def snap_to_grid(v : Float32) : Float32
    (v / SNAP_GRID).round * SNAP_GRID
  end

  # True if two rectangles overlap (share any area).
  private def rects_overlap?(a : R::Rectangle, b : R::Rectangle) : Bool
    a.x < b.x + b.width && a.x + a.width > b.x &&
      a.y < b.y + b.height && a.y + a.height > b.y
  end

  # If the selected element is a TextElement with empty text, remove it and
  # return its former index so callers can adjust other indices. Returns nil
  # when no cleanup was needed.
  private def cleanup_empty_text_selection : Int32?
    idx = @selected_index
    return nil unless idx
    el = @elements[idx]
    return nil unless el.is_a?(TextElement) && el.text.empty?
    @elements.delete_at(idx)
    @selected_index = nil
    idx
  end

  # Returns the index of the topmost element under *mouse_world*, or nil.
  # Non-arrow elements use bounding-rect containment; arrows use a
  # zoom-aware line-proximity test so the click target stays constant in
  # screen pixels regardless of zoom level.
  private def hit_test_element(mouse_world : R::Vector2) : Int32?
    arrow_threshold = 6.0_f32 / @camera.zoom
    (@elements.size - 1).downto(0) do |i|
      el = @elements[i]
      hit = el.is_a?(ArrowElement) ? el.near_line?(mouse_world, arrow_threshold) : el.contains?(mouse_world)
      return i if hit
    end
    nil
  end

  # Returns which resize handle the mouse is over, or nil.
  private def hit_test_handles(mouse_world : R::Vector2) : Handle?
    return nil unless (idx = @selected_index)
    return nil unless idx < @elements.size
    return nil unless @elements[idx].resizable?
    half = (HANDLE_SIZE / 2.0_f32) / @camera.zoom
    handle_positions(@elements[idx].bounds).each do |(handle, center)|
      return handle if (mouse_world.x - center.x).abs <= half &&
                       (mouse_world.y - center.y).abs <= half
    end
    nil
  end

  # Returns the 8 handle positions (world space) for *b*.
  private def handle_positions(b : R::Rectangle)
    x1, y1 = b.x, b.y
    x2, y2 = b.x + b.width, b.y + b.height
    xm, ym = b.x + b.width / 2.0_f32, b.y + b.height / 2.0_f32
    [
      {Handle::NW, R::Vector2.new(x: x1, y: y1)},
      {Handle::N, R::Vector2.new(x: xm, y: y1)},
      {Handle::NE, R::Vector2.new(x: x2, y: y1)},
      {Handle::E, R::Vector2.new(x: x2, y: ym)},
      {Handle::SE, R::Vector2.new(x: x2, y: y2)},
      {Handle::S, R::Vector2.new(x: xm, y: y2)},
      {Handle::SW, R::Vector2.new(x: x1, y: y2)},
      {Handle::W, R::Vector2.new(x: x1, y: ym)},
    ]
  end

  # Compute new bounds after dragging *handle* from *sm* to *mouse*.
  # *min_w* / *min_h* set the smallest allowed dimensions (e.g. label footprint).
  private def apply_resize(handle : Handle, orig : R::Rectangle, sm : R::Vector2, mouse : R::Vector2,
                           min_w : Float32 = 4.0_f32, min_h : Float32 = 4.0_f32) : R::Rectangle
    dx = mouse.x - sm.x
    dy = mouse.y - sm.y
    x, y, w, h = orig.x, orig.y, orig.width, orig.height

    # Left edge (NW, W, SW) — clamp width and keep right edge fixed.
    if handle.nw? || handle.w? || handle.sw?
      w = (orig.width - dx).clamp(min_w, Float32::MAX)
      x = orig.x + orig.width - w
    end
    # Right edge (NE, E, SE) — clamp width, left edge stays.
    if handle.ne? || handle.e? || handle.se?
      w = (orig.width + dx).clamp(min_w, Float32::MAX)
    end
    # Top edge (NW, N, NE) — clamp height and keep bottom edge fixed.
    if handle.nw? || handle.n? || handle.ne?
      h = (orig.height - dy).clamp(min_h, Float32::MAX)
      y = orig.y + orig.height - h
    end
    # Bottom edge (SW, S, SE) — clamp height, top edge stays.
    if handle.sw? || handle.s? || handle.se?
      h = (orig.height + dy).clamp(min_h, Float32::MAX)
    end

    R::Rectangle.new(x: x, y: y, width: w, height: h)
  end
end
