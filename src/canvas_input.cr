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
    mouse_screen = R.get_mouse_position
    mouse_world  = R.get_screen_to_world_2d(mouse_screen, @camera)

    if R.mouse_button_pressed?(R::MouseButton::Left)
      if @block_mouse_press
        @block_mouse_press = false
        return
      end
      now = R.get_time
      is_double_click = (now - @last_click_time) < DOUBLE_CLICK_TIME &&
        (@last_click_screen.x - mouse_screen.x).abs < DOUBLE_CLICK_DIST &&
        (@last_click_screen.y - mouse_screen.y).abs < DOUBLE_CLICK_DIST
      @last_click_time   = now
      @last_click_screen = mouse_screen
      @mode = @mode.on_mouse_press(self, mouse_world, mouse_screen, is_double_click)
    elsif R.mouse_button_down?(R::MouseButton::Left)
      @mode = @mode.on_mouse_drag(self, mouse_world)
    elsif R.mouse_button_released?(R::MouseButton::Left)
      @mode = @mode.on_mouse_release(self, mouse_world)
    end
  end

  private def handle_text_input
    return if @mode.text_selecting?
    return unless @mode.accepts_text_input?
    return unless (idx = @selected_index)
    return unless @text_session_id
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
      next if code == 13  # Enter is handled explicitly below; skip to avoid double-fire
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

    refresh_element_layout(el)

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
        emit_text_event(TextChangedEvent.new(id, text_after, bounds_now, cursor_before)) if text_before != text_after
      else
        # Single char insert with no prior selection: coalesce into a word group.
        ch        = chars_typed[0]
        now       = R.get_time
        timed_out = now - @text_coalesce_time > COALESCE_TIMEOUT
        boundary  = !@text_coalesce_text.empty? &&
                    !ch.whitespace? && @text_coalesce_text[-1].whitespace?
        flush_text_coalesce if @text_coalesce_id != id || timed_out || boundary
        @text_coalesce_id     = id      if @text_coalesce_id.nil?
        @text_coalesce_pos    = cursor_before if @text_coalesce_text.empty?
        @text_coalesce_text  += ch.to_s
        @text_coalesce_bounds = bounds_now
        @text_coalesce_time   = now
      end

    when :backspace
      flush_text_coalesce
      if text_before != text_after
        if had_selection
          emit_text_event(TextChangedEvent.new(id, text_after, bounds_now, cursor_before))
        else
          emit_text_event(DeleteTextEvent.new(id, cursor_after, cursor_before - cursor_after, bounds_now, cursor_before))
        end
      end

    when :backspace_word, :cut
      flush_text_coalesce
      emit_text_event(TextChangedEvent.new(id, text_after, bounds_now, cursor_before)) if text_before != text_after

    when :paste
      flush_text_coalesce
      if text_before != text_after
        pt = paste_text
        if had_selection || pt.nil?
          emit_text_event(TextChangedEvent.new(id, text_after, bounds_now, cursor_before))
        else
          emit_text_event(InsertTextEvent.new(id, cursor_before, pt, bounds_now))
        end
      end

    when :cursor
      flush_text_coalesce  # cursor movement is always a word boundary
    end
  end

  private def handle_delete
    return if @mode.text_selecting?
    return unless R.key_pressed?(R::KeyboardKey::Delete) || R.key_pressed_repeat?(R::KeyboardKey::Delete)
    ctrl = R.key_down?(R::KeyboardKey::LeftControl) || R.key_down?(R::KeyboardKey::RightControl)
    if @text_session_id && (idx = @selected_index)
      # In text editing mode: forward-delete (char or word to the right of the cursor).
      el = @elements[idx]
      case el
      when TextElement, RectElement
        text_before   = editing_text_for(el)
        cursor_start  = el.cursor_pos
        had_selection = !el.selection_range.nil?
        ctrl ? el.handle_forward_delete_word : el.handle_forward_delete
        refresh_element_layout(el)
        text_after = editing_text_for(el)
        if text_before != text_after
          b  = el.bounds
          bd = BoundsData.new(b.x, b.y, b.width, b.height)
          flush_text_coalesce
          if had_selection || ctrl
            emit_text_event(TextChangedEvent.new(el.id, text_after, bd, cursor_start))
          else
            emit_text_event(DeleteTextEvent.new(el.id, cursor_start, 1, bd, cursor_start))
          end
        end
      end
    elsif multi_selected?
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
  def emit_text_event(event : CanvasEvent) : Nil
    apply(@model, event)
    @history.push(event)
    @render_data = @layout_engine.layout(@model)
    # Inject updated cache into the live text element (model text is now in sync).
    if (sid = @text_session_id)
      rd = @render_data[sid]?
      if rd.is_a?(TextRenderData)
        el = @elements.find { |e| e.id == sid }
        if el.is_a?(TextElement)
          el.cached_line_runs = rd.line_runs
          el.cached_wraps     = rd.wraps
          el.bounds = R::Rectangle.new(x: rd.bounds.x, y: rd.bounds.y,
                                        width: rd.bounds.w, height: rd.bounds.h)
        end
      end
    end
  end

  # Emit the coalescing buffer as a single InsertTextEvent and clear it.
  def flush_text_coalesce : Nil
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

  private def handle_escape
    return unless R.key_pressed?(R::KeyboardKey::Escape)
    @mode = @mode.on_escape(self)
  end

  private def handle_quit
    ctrl = R.key_down?(R::KeyboardKey::LeftControl) || R.key_down?(R::KeyboardKey::RightControl)
    @quit_requested = true if ctrl && R.key_pressed?(R::KeyboardKey::Q)
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
    if @text_session_id
      flush_text_coalesce
      undone_event = @history.last_event
      return unless (restored = @history.undo)
      @model = restored
      sync_elements_from_model
      if @text_session_id
        restore_cursor_after_undo(undone_event)
      else
        @mode = IdleMode.new(cursor_tool)
      end
    else
      commit_text_session_if_active
      return unless (restored = @history.undo)
      @model           = restored
      @text_session_id = nil
      @mode            = IdleMode.new(cursor_tool)
      sync_elements_from_model
    end
  end

  private def perform_redo
    if @text_session_id
      flush_text_coalesce
      redo_event = @history.last_redo_event
      return unless (restored = @history.redo)
      @model = restored
      sync_elements_from_model
      if @text_session_id
        restore_cursor_after_redo(redo_event)
      else
        @mode = IdleMode.new(cursor_tool)
      end
    else
      commit_text_session_if_active
      return unless (restored = @history.redo)
      @model           = restored
      @text_session_id = nil
      @mode            = IdleMode.new(cursor_tool)
      sync_elements_from_model
    end
  end

  private def restore_cursor_after_undo(event : CanvasEvent?) : Nil
    return unless (idx = @selected_index)
    return unless (el = @elements[idx]?)
    return unless el.responds_to?(:set_selection)
    pos = case event
          when InsertTextEvent  then event.position
          when DeleteTextEvent  then event.cursor_before
          when TextChangedEvent then event.cursor_before
          else                       el.cursor_pos
          end
    max_pos = el.responds_to?(:editing_text) ? el.editing_text.chars.size : 0
    clamped = pos.clamp(0, max_pos)
    el.set_selection(clamped, clamped)
    el.clear_selection
  end

  private def restore_cursor_after_redo(event : CanvasEvent?) : Nil
    return unless (idx = @selected_index)
    return unless (el = @elements[idx]?)
    return unless el.responds_to?(:set_selection)
    pos = case event
          when InsertTextEvent  then event.position + event.text.chars.size
          when DeleteTextEvent  then event.start
          when TextChangedEvent then el.cursor_pos
          else                       el.cursor_pos
          end
    max_pos = el.responds_to?(:editing_text) ? el.editing_text.chars.size : 0
    clamped = pos.clamp(0, max_pos)
    el.set_selection(clamped, clamped)
    el.clear_selection
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

  # Switch cursor tool with S / R / T / A. Guarded while an element is selected so
  # the keys remain available for text input when editing.
  private def handle_tool_switch
    return if @selected_index
    tool = if R.key_pressed?(R::KeyboardKey::S)
      CursorTool::Selection
    elsif R.key_pressed?(R::KeyboardKey::R)
      CursorTool::Rect
    elsif R.key_pressed?(R::KeyboardKey::T)
      CursorTool::Text
    elsif R.key_pressed?(R::KeyboardKey::A)
      CursorTool::Arrow
    else
      return
    end
    @selected_indices = [] of Int32
    @selected_ids     = [] of UUID
    @mode = IdleMode.new(tool)
  end

  # Changes @selected_index, clearing any text selection on the element losing focus.
  # Commits any in-flight text session and tracks the new selection by UUID.
  # Also clears multi-selection.
  def select_element(new_idx : Int32?)
    old_idx = @selected_index
    @selected_indices = [] of Int32
    @selected_ids = [] of UUID
    if old_idx != new_idx
      commit_text_session_if_active
      @elements[old_idx].clear_selection if old_idx && old_idx < @elements.size
      if new_idx && (el = @elements[new_idx]?)
        @selected_index  = new_idx
        @selected_id     = el.id
        @text_session_id = nil
      else
        @selected_index  = nil
        @selected_id     = nil
        @text_session_id = nil
      end
    end
  end

  # Activates multi-selection, committing any text session and clearing single selection.
  def select_multi(indices : Array(Int32))
    old_idx = @selected_index
    commit_text_session_if_active
    @elements[old_idx].clear_selection if old_idx && old_idx < @elements.size
    @selected_index  = nil
    @selected_id     = nil
    @text_session_id = nil
    @selected_indices = indices
    @selected_ids     = indices.compact_map { |i| @elements[i]?.try(&.id) }
  end

  # Adds *click_idx* to the current selection, or removes it if already present.
  # Promotes a single selection to multi-selection when a second element is added.
  # Commits any active text session first.
  def toggle_element_in_selection(click_idx : Int32)
    commit_text_session_if_active
    current = if multi_selected?
      @selected_indices.dup
    elsif (si = @selected_index)
      [si]
    else
      [] of Int32
    end
    if current.includes?(click_idx)
      current.delete(click_idx)
    else
      current << click_idx
    end
    if current.empty?
      select_element(nil)
    elsif current.size == 1
      select_element(current.first)
    else
      select_multi(current)
    end
  end

  # Returns true when more than one element is selected.
  def multi_selected? : Bool
    @selected_indices.size > 1
  end

  # Returns true if *idx* is part of the current multi-selection.
  def in_multi_selection?(idx : Int32) : Bool
    @selected_indices.includes?(idx)
  end

  # Clears multi-selection without affecting single selection.
  def clear_multi_selection : Nil
    @selected_indices = [] of Int32
    @selected_ids     = [] of UUID
  end

  # Snaps *v* to the nearest snap-grid line.
  def snap_to_grid(v : Float32) : Float32
    (v / SNAP_GRID).round * SNAP_GRID
  end

  # True if two rectangles overlap (share any area).
  def rects_overlap?(a : R::Rectangle, b : R::Rectangle) : Bool
    a.x < b.x + b.width && a.x + a.width > b.x &&
      a.y < b.y + b.height && a.y + a.height > b.y
  end

  # If the selected element is a TextElement with empty text, remove it and
  # return its former index so callers can adjust other indices. Returns nil
  # when no cleanup was needed.
  def cleanup_empty_text_selection : Int32?
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
  def hit_test_rect_label(el : RectElement, mouse_world : R::Vector2) : Bool
    rd = @render_data[el.id]?
    return false unless rd.is_a?(RectRenderData)
    lines = rd.label_lines
    return false if lines.empty? || lines.all? { |(text, _)| text.empty? }
    total_h = (lines.size * RectElement::LABEL_FONT_SIZE).to_f32
    max_w   = lines.map { |(_, w)| w.to_f32 }.max
    cx = el.bounds.x + el.bounds.width / 2.0_f32
    cy = el.bounds.y + el.bounds.height / 2.0_f32
    mouse_world.x >= cx - max_w / 2.0_f32 && mouse_world.x <= cx + max_w / 2.0_f32 &&
      mouse_world.y >= cy - total_h / 2.0_f32 && mouse_world.y <= cy + total_h / 2.0_f32
  end

  def hit_test_element(mouse_world : R::Vector2) : Int32?
    arrow_threshold = 6.0_f32 / @camera.zoom
    (@elements.size - 1).downto(0) do |i|
      el  = @elements[i]
      hit = if el.is_a?(ArrowElement)
        rd = @render_data[el.id]?
        rd.is_a?(ArrowRenderData) && arrow_near_point?(rd.waypoints, mouse_world, arrow_threshold)
      else
        el.contains?(mouse_world)
      end
      return i if hit
    end
    nil
  end

  private def arrow_near_point?(waypoints : Array({Float32, Float32}), p : R::Vector2, threshold : Float32) : Bool
    (waypoints.size - 1).times.any? do |i|
      a = R::Vector2.new(x: waypoints[i][0],     y: waypoints[i][1])
      b = R::Vector2.new(x: waypoints[i + 1][0], y: waypoints[i + 1][1])
      segment_dist(p, a, b) <= threshold
    end
  end

  private def segment_dist(p : R::Vector2, a : R::Vector2, b : R::Vector2) : Float32
    dx = b.x - a.x
    dy = b.y - a.y
    len_sq = dx * dx + dy * dy
    if len_sq < 0.001_f32
      return Math.sqrt((p.x - a.x)**2 + (p.y - a.y)**2).to_f32
    end
    t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / len_sq
    t = t.clamp(0.0_f32, 1.0_f32)
    Math.sqrt((p.x - (a.x + t * dx))**2 + (p.y - (a.y + t * dy))**2).to_f32
  end

  # Returns which resize handle the mouse is over, or nil.
  # Width-only elements (TextElement) expose only the left and right edge handles.
  def hit_test_handles(mouse_world : R::Vector2) : Handle?
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
  def apply_resize(handle : Handle, orig : R::Rectangle, sm : R::Vector2, mouse : R::Vector2,
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

  def rect_from_points(a : R::Vector2, b : R::Vector2) : R::Rectangle
    x = Math.min(a.x, b.x)
    y = Math.min(a.y, b.y)
    w = (a.x - b.x).abs
    h = (a.y - b.y).abs
    R::Rectangle.new(x: x, y: y, width: w, height: h)
  end
end
