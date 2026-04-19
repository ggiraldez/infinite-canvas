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
          # For TextElements, lock in the user-chosen width and re-flow height live.
          if el.is_a?(TextElement)
            el.fixed_width = true
            el.fit_content
          end
        end
      end

    elsif R.mouse_button_released?(R::MouseButton::Left)
      case @drag_mode
      when DragMode::Selecting
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
        @draw_start   = nil
        @draw_current = nil

      when DragMode::Connecting
        # Create an arrow if the mouse was released over a different non-arrow element.
        if (src_idx = @arrow_source_index) && (tgt_idx = hit_test_element(mouse_world))
          if tgt_idx != src_idx && !@elements[tgt_idx].is_a?(ArrowElement)
            from_id  = @elements[src_idx].id
            to_id    = @elements[tgt_idx].id
            arrow_id = UUID.random
            emit(CreateArrowEvent.new(arrow_id, from_id, to_id))
            @active_tool = ActiveTool::Selection
          end
        end
        @arrow_source_index = nil
        @draw_start         = nil
        @draw_current       = nil

      when DragMode::Drawing
        if (start = @draw_start) && (current = @draw_current)
          dragged = rect_from_points(start, current)
          is_drag = dragged.width >= 4.0_f32 || dragged.height >= 4.0_f32
          maw     = R.get_screen_width.to_f32 / (2.0_f32 * @camera.zoom)

          case @active_tool
          when ActiveTool::Rect
            b = is_drag ? dragged
                        : R::Rectangle.new(x: start.x, y: start.y,
                                           width: DEFAULT_RECT_W, height: DEFAULT_RECT_H)
            rect_id = UUID.random
            fill    = ColorData.new(90_u8, 140_u8, 220_u8, 200_u8)
            stroke  = ColorData.new(30_u8, 60_u8, 120_u8, 255_u8)
            event   = CreateRectEvent.new(rect_id,
                        BoundsData.new(b.x, b.y, b.width, b.height), fill, stroke, 2.0_f32)
            emit(event)
            select_element(@elements.index { |e| e.id == rect_id })
            @active_tool = ActiveTool::Selection

          when ActiveTool::Text
            raw = is_drag ? R::Rectangle.new(x: start.x, y: start.y,
                                             width: dragged.width, height: dragged.height)
                          : R::Rectangle.new(x: start.x, y: start.y,
                                             width: 0.0_f32, height: 0.0_f32)
            text_id = UUID.random
            # Create a temporary element solely to compute fit_content bounds.
            tmp = TextElement.new(raw, "", text_id)
            tmp.max_auto_width = maw
            tmp.fit_content
            fb    = tmp.bounds
            event = CreateTextEvent.new(text_id,
                      BoundsData.new(fb.x, fb.y, fb.width, fb.height), "", false, maw)
            emit(event)
            select_element(@elements.index { |e| e.id == text_id })
            @active_tool = ActiveTool::Selection
          end
        end
        @draw_start   = nil
        @draw_current = nil

      when DragMode::Moving
        # Commit text session first so the sync doesn't overwrite live-edited text.
        commit_text_session_if_active
        if (starts = @multi_drag_starts) && @selected_indices.size > 1
          moves = @selected_indices.map do |i|
            el = @elements[i]
            b  = el.bounds
            {el.id, BoundsData.new(b.x, b.y, b.width, b.height)}
          end
          emit(MoveMultiEvent.new(moves))
          # Restore text session if the moved element was being edited (unlikely but safe).
          if (si = @selected_index) && (new_el = @elements[si]?)
            @text_session_id = (new_el.is_a?(TextElement) || new_el.is_a?(RectElement)) ? new_el.id : nil
          end
        elsif (idx = @selected_index)
          el = @elements[idx]
          b  = el.bounds
          emit(MoveElementEvent.new(el.id, BoundsData.new(b.x, b.y, b.width, b.height)))
          # Restore text session so the user can keep editing after dragging.
          if (si = @selected_index) && (new_el = @elements[si]?)
            @text_session_id = (new_el.is_a?(TextElement) || new_el.is_a?(RectElement)) ? new_el.id : nil
          end
        end

      when DragMode::Resizing
        # Commit text session first (resize triggers a sync that would drop live text).
        commit_text_session_if_active
        if (idx = @selected_index)
          el = @elements[idx]
          b  = el.bounds
          emit(ResizeElementEvent.new(el.id, BoundsData.new(b.x, b.y, b.width, b.height)))
          # Restore text session so the user can keep editing after resizing.
          if (si = @selected_index) && (new_el = @elements[si]?)
            @text_session_id = (new_el.is_a?(TextElement) || new_el.is_a?(RectElement)) ? new_el.id : nil
          end
        end
      end

      @drag_mode        = DragMode::None
      @drag_start_mouse = nil
      @drag_start_bounds = nil
      @active_handle    = nil
      @multi_drag_starts = nil
    end
  end

  private def handle_text_input
    return unless (idx = @selected_index)
    el = @elements[idx]
    id = el.id

    # Snapshot before any operations this frame.
    text_before   = editing_text_for(el)
    cursor_before = el.cursor_pos
    had_selection = !el.selection_range.nil?
    last_op       = :none  # :char | :backspace | :backspace_word | :paste | :cut | :cursor

    # ── Char input ─────────────────────────────────────────────────────────────
    chars_typed = ""
    while (code = R.get_char_pressed) > 0
      chars_typed += code.chr.to_s
      el.handle_char_input(code.chr)
      last_op = :char
    end
    if R.key_pressed?(R::KeyboardKey::Enter) || R.key_pressed_repeat?(R::KeyboardKey::Enter)
      chars_typed += "\n"
      el.handle_enter
      last_op = :char
    end

    # ── Delete ─────────────────────────────────────────────────────────────────
    ctrl  = R.key_down?(R::KeyboardKey::LeftControl) || R.key_down?(R::KeyboardKey::RightControl)
    shift = R.key_down?(R::KeyboardKey::LeftShift)   || R.key_down?(R::KeyboardKey::RightShift)

    if R.key_pressed?(R::KeyboardKey::Backspace) || R.key_pressed_repeat?(R::KeyboardKey::Backspace)
      if ctrl
        el.handle_backspace_word
        last_op = :backspace_word
      else
        el.handle_backspace
        last_op = :backspace
      end
    end

    # ── Clipboard ──────────────────────────────────────────────────────────────
    paste_text = nil
    if ctrl && R.key_pressed?(R::KeyboardKey::C)
      if (copied = el.handle_copy); R.set_clipboard_text(copied); end
    end
    if ctrl && R.key_pressed?(R::KeyboardKey::X)
      if (cut = el.handle_cut)
        R.set_clipboard_text(cut)
        last_op = :cut
      end
    end
    if ctrl && (R.key_pressed?(R::KeyboardKey::V) || R.key_pressed_repeat?(R::KeyboardKey::V))
      cb = String.new(R.get_clipboard_text.as(Pointer(UInt8)))
      unless cb.empty?
        paste_text = cb
        el.handle_paste(cb)
        last_op = :paste
      end
    end

    # ── Cursor movement ─────────────────────────────────────────────────────────
    if R.key_pressed?(R::KeyboardKey::Left) || R.key_pressed_repeat?(R::KeyboardKey::Left)
      ctrl ? el.handle_cursor_word_left(shift) : el.handle_cursor_left(shift)
      last_op = :cursor if last_op == :none
    end
    if R.key_pressed?(R::KeyboardKey::Right) || R.key_pressed_repeat?(R::KeyboardKey::Right)
      ctrl ? el.handle_cursor_word_right(shift) : el.handle_cursor_right(shift)
      last_op = :cursor if last_op == :none
    end
    if R.key_pressed?(R::KeyboardKey::Up) || R.key_pressed_repeat?(R::KeyboardKey::Up)
      el.handle_cursor_up(shift)
      last_op = :cursor if last_op == :none
    end
    if R.key_pressed?(R::KeyboardKey::Down) || R.key_pressed_repeat?(R::KeyboardKey::Down)
      el.handle_cursor_down(shift)
      last_op = :cursor if last_op == :none
    end

    if el.is_a?(TextElement)
      el.max_auto_width = R.get_screen_width.to_f32 / (2.0_f32 * @camera.zoom)
    end
    el.fit_content

    return if last_op == :none

    text_after  = editing_text_for(el)
    b           = el.bounds
    bounds_now  = BoundsData.new(b.x, b.y, b.width, b.height)
    cursor_after = el.cursor_pos

    case last_op
    when :char
      if had_selection || chars_typed.size != 1
        # Selection replace or multiple chars in one frame: full-state event.
        flush_text_coalesce
        emit_text_event(TextChangedEvent.new(id, text_after, bounds_now)) if text_before != text_after
      else
        # Single char insert with no prior selection: coalesce into a word group.
        ch        = chars_typed[0]
        timed_out = R.get_time - @text_coalesce_time > COALESCE_TIMEOUT
        boundary  = !@text_coalesce_text.empty? &&
                    !ch.whitespace? && @text_coalesce_text[-1].whitespace?
        flush_text_coalesce if @text_coalesce_id != id || timed_out || boundary
        @text_coalesce_id     = id      if @text_coalesce_id.nil?
        @text_coalesce_pos    = cursor_before if @text_coalesce_text.empty?
        @text_coalesce_text  += ch.to_s
        @text_coalesce_bounds = bounds_now
        @text_coalesce_time   = R.get_time
      end

    when :backspace
      flush_text_coalesce
      if text_before != text_after
        if had_selection
          emit_text_event(TextChangedEvent.new(id, text_after, bounds_now))
        else
          emit_text_event(DeleteTextEvent.new(id, cursor_after, cursor_before - cursor_after, bounds_now))
        end
      end

    when :backspace_word, :cut
      flush_text_coalesce
      emit_text_event(TextChangedEvent.new(id, text_after, bounds_now)) if text_before != text_after

    when :paste
      flush_text_coalesce
      if text_before != text_after
        pt = paste_text
        if had_selection || pt.nil?
          emit_text_event(TextChangedEvent.new(id, text_after, bounds_now))
        else
          emit_text_event(InsertTextEvent.new(id, cursor_before, pt, bounds_now))
        end
      end

    when :cursor
      flush_text_coalesce  # cursor movement is always a word boundary
    end
  end

  private def handle_delete
    return unless R.key_pressed?(R::KeyboardKey::Delete) || R.key_pressed_repeat?(R::KeyboardKey::Delete)
    if multi_selected?
      # Emit one DeleteElementEvent per selected element; apply() cascades arrow removal.
      events = @selected_indices.map { |i| DeleteElementEvent.new(@elements[i].id) }
      events.each { |ev| apply(@model, ev); @history.push(ev) }
      @selected_indices = [] of Int32
      @selected_ids     = [] of UUID
      sync_elements_from_model
    elsif (idx = @selected_index)
      @text_session_id = nil  # discard any text session — element is gone
      emit(DeleteElementEvent.new(@elements[idx].id))
    end
  end

  # Applies a text event to the model + history without triggering sync.
  # During a text session the element is the live source of truth; syncing
  # would lose cursor position. Model and element stay in step via these events.
  private def emit_text_event(event : CanvasEvent) : Nil
    apply(@model, event)
    @history.push(event)
  end

  # Emit the coalescing buffer as a single InsertTextEvent and clear it.
  private def flush_text_coalesce : Nil
    return if @text_coalesce_text.empty?
    id = @text_coalesce_id || return
    emit_text_event(InsertTextEvent.new(id, @text_coalesce_pos,
                      @text_coalesce_text, @text_coalesce_bounds))
    @text_coalesce_id   = nil
    @text_coalesce_text = ""
  end

  # Returns the editable text of an element (label for rects, text for text nodes).
  private def editing_text_for(el : Element) : String
    case el
    when TextElement then el.text
    when RectElement then el.label
    else                  ""
    end
  end

  private def handle_undo_redo
    ctrl = R.key_down?(R::KeyboardKey::LeftControl) || R.key_down?(R::KeyboardKey::RightControl)
    return unless ctrl
    if R.key_pressed?(R::KeyboardKey::Z)
      shift = R.key_down?(R::KeyboardKey::LeftShift) || R.key_down?(R::KeyboardKey::RightShift)
      shift ? perform_redo : perform_undo
    elsif R.key_pressed?(R::KeyboardKey::Y)
      perform_redo
    end
  end

  private def perform_undo
    commit_text_session_if_active
    return unless (restored = @history.undo)
    @model           = restored
    @text_session_id = nil
    sync_elements_from_model
  end

  private def perform_redo
    commit_text_session_if_active
    return unless (restored = @history.redo)
    @model           = restored
    @text_session_id = nil
    sync_elements_from_model
  end

  # Toggle the routing style of the selected arrow with Tab.
  private def handle_arrow_style_toggle
    return unless (idx = @selected_index)
    return unless R.key_pressed?(R::KeyboardKey::Tab)
    el = @elements[idx]
    return unless el.is_a?(ArrowElement)
    new_style = el.routing_style.straight? ? "orthogonal" : "straight"
    emit(ArrowRoutingChangedEvent.new(el.id, new_style))
  end

  # Switch active tool with S / R / T / A. Guarded while an element is selected so
  # the keys remain available for text input when editing.
  private def handle_tool_switch
    return if @selected_index
    if R.key_pressed?(R::KeyboardKey::S)
      @selected_indices = [] of Int32
      @selected_ids     = [] of UUID
      @active_tool = ActiveTool::Selection
    elsif R.key_pressed?(R::KeyboardKey::R)
      @selected_indices = [] of Int32
      @selected_ids     = [] of UUID
      @active_tool = ActiveTool::Rect
    elsif R.key_pressed?(R::KeyboardKey::T)
      @selected_indices = [] of Int32
      @selected_ids     = [] of UUID
      @active_tool = ActiveTool::Text
    elsif R.key_pressed?(R::KeyboardKey::A)
      @selected_indices = [] of Int32
      @selected_ids     = [] of UUID
      @active_tool = ActiveTool::Arrow
    end
  end

  # Changes @selected_index, clearing any text selection on the element losing focus.
  # Commits any in-flight text session and tracks the new selection by UUID.
  # Also clears multi-selection.
  private def select_element(new_idx : Int32?)
    old_idx = @selected_index
    @selected_indices = [] of Int32
    @selected_ids = [] of UUID
    if old_idx != new_idx
      commit_text_session_if_active
      @elements[old_idx].clear_selection if old_idx && old_idx < @elements.size
      @selected_index = new_idx
      if new_idx && (el = @elements[new_idx]?)
        @selected_id     = el.id
        @text_session_id = (el.is_a?(TextElement) || el.is_a?(RectElement)) ? el.id : nil
      else
        @selected_id     = nil
        @text_session_id = nil
      end
    end
  end

  # Activates multi-selection, committing any text session and clearing single selection.
  private def select_multi(indices : Array(Int32))
    old_idx = @selected_index
    commit_text_session_if_active
    @elements[old_idx].clear_selection if old_idx && old_idx < @elements.size
    @selected_index  = nil
    @selected_id     = nil
    @text_session_id = nil
    @selected_indices = indices
    @selected_ids     = indices.compact_map { |i| @elements[i]?.try(&.id) }
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
    removed_at = idx
    @text_session_id = nil  # discard empty session without committing
    emit(DeleteElementEvent.new(el.id))
    # After emit+sync: @selected_index and @selected_id are nil (element not found).
    removed_at
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
  # Width-only elements (TextElement) expose only the left and right edge handles.
  private def hit_test_handles(mouse_world : R::Vector2) : Handle?
    return nil unless (idx = @selected_index)
    return nil unless idx < @elements.size
    el = @elements[idx]
    return nil unless el.resizable?
    half = (HANDLE_SIZE / 2.0_f32) / @camera.zoom
    handles = el.resizable_width_only? ?
      handle_positions(el.bounds).select { |(h, _)| h.e? || h.w? } :
      handle_positions(el.bounds)
    handles.each do |(handle, center)|
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
