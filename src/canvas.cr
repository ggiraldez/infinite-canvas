require "json"
require "raylib-cr"
require "./element"
require "./persistence"

# Infinite canvas: owns the Camera2D, the element list, and input handling.
class Canvas
  GRID_SPACING     =  50.0_f32
  GRID_COLOR_MINOR = R::Color.new(r: 235, g: 235, b: 235, a: 255)
  GRID_COLOR_MAJOR = R::Color.new(r: 210, g: 210, b: 210, a: 255)
  BACKGROUND       = R::Color.new(r: 250, g: 250, b: 250, a: 255)
  DRAFT_FILL       = R::Color.new(r: 90, g: 140, b: 220, a: 80)
  DRAFT_STROKE     = R::Color.new(r: 30, g: 60, b: 120, a: 200)
  SEL_COLOR        = R::Color.new(r: 0, g: 120, b: 255, a: 255)
  HANDLE_SIZE      =   8.0_f32 # constant screen-space pixels
  DEFAULT_RECT_W   = 160.0_f32 # default width when a rect is created by click
  DEFAULT_RECT_H   = 100.0_f32 # default height when a rect is created by click
  SAVE_FILE        = "canvas.json"
  # Discrete zoom steps: a geometric series of 2^(i/4) filtered to [0.1, 10.0].
  # Four steps per octave gives smooth scrolling while guaranteeing that every
  # exact power of two (0.125, 0.25, 0.5, 1.0, 2.0, 4.0, 8.0) is always
  # reachable — they fall on multiples of 4 quarter-octave steps.
  ZOOM_LEVELS = (-14..14)
    .map { |i| 2.0_f32 ** (i.to_f32 * 0.25_f32) }
    .select { |z| z >= 0.1_f32 && z <= 10.0_f32 }

  enum DragMode
    None
    Drawing
    Moving
    Resizing
    Connecting  # Arrow tool: dragging from a source element to a target element
  end

  enum Handle
    NW; N; NE; E; SE; S; SW; W
  end

  enum ActiveTool
    Selection
    Rect
    Text
    Arrow
  end

  getter elements : Array(Element)
  getter camera : R::Camera2D
  property active_tool : ActiveTool = ActiveTool::Selection

  def selected_element : Element?
    (idx = @selected_index) ? @elements[idx]? : nil
  end

  @drag_mode : DragMode = DragMode::None
  @selected_index : Int32? = nil

  # Drawing state
  @draw_start : R::Vector2?
  @draw_current : R::Vector2?

  # Move / resize state
  @drag_start_mouse : R::Vector2?
  @drag_start_bounds : R::Rectangle?
  @active_handle : Handle?

  # Arrow-connecting state: index of the source element while dragging a new arrow.
  @arrow_source_index : Int32? = nil

  def initialize(screen_width : Int32, screen_height : Int32)
    @elements = [] of Element
    @camera = R::Camera2D.new(
      offset: R::Vector2.new(x: screen_width / 2.0_f32, y: screen_height / 2.0_f32),
      target: R::Vector2.new(x: 0.0_f32, y: 0.0_f32),
      rotation: 0.0_f32,
      zoom: 1.0_f32,
    )
  end

  def save
    json_str = JSON.build do |json|
      json.object do
        json.field "elements" do
          json.array do
            @elements.each do |e|
              case e
              when RectElement  then RectElementData.new(e).to_json(json)
              when TextElement  then TextElementData.new(e).to_json(json)
              when ArrowElement then ArrowElementData.new(e).to_json(json)
              end
            end
          end
        end
      end
    end
    File.write(SAVE_FILE, json_str)
  rescue ex
    STDERR.puts "Warning: could not save canvas — #{ex.message}"
  end

  def load
    return unless File.exists?(SAVE_FILE)
    raw = JSON.parse(File.read(SAVE_FILE))
    # Support legacy "rects" key from older save files (items default to type "rect").
    items = (raw["elements"]? || raw["rects"]?).try(&.as_a?) || return
    @elements = items.compact_map do |item|
      type = item["type"]?.try(&.as_s?) || "rect"
      data = item.to_json
      case type
      when "rect"  then RectElementData.from_json(data).to_element.as(Element)
      when "text"  then TextElementData.from_json(data).to_element.as(Element)
      when "arrow" then ArrowElementData.from_json(data).to_element(@elements).as(Element)
      end
    end
    # compact_map returns a new array assigned to @elements after the block
    # finishes, so arrows constructed inside the block hold a reference to the
    # old array. Patch them here to point at the live one.
    @elements.each { |e| e.elements = @elements if e.is_a?(ArrowElement) }
  rescue ex
    STDERR.puts "Warning: could not load canvas — #{ex.message}"
  end

  def update
    handle_pan
    handle_zoom
    handle_left_mouse
    handle_text_input
    handle_delete
    handle_tool_switch
    handle_arrow_style_toggle
  end

  def draw
    R.begin_mode_2d(@camera)
    draw_grid
    # Arrows first so they appear behind shapes and text.
    @elements.each { |e| e.draw if e.is_a?(ArrowElement) }
    @elements.each { |e| e.draw unless e.is_a?(ArrowElement) }
    draw_selection
    draw_draft
    R.end_mode_2d
  end

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
          # If the clicked element was itself an empty text node, clean it up and
          # skip selection. Otherwise adjust the index if cleanup shifted things.
          removed_at = cleanup_empty_text_selection
          unless removed_at == idx
            idx -= 1 if removed_at && idx > removed_at
            @selected_index = idx
            @drag_mode = DragMode::Moving
            @drag_start_mouse = mouse_world
            @drag_start_bounds = @elements[idx].bounds
          end
        else
          # Empty space: clear selection. Drag is reserved for future multi-select.
          cleanup_empty_text_selection
          @selected_index = nil
        end
      elsif @active_tool.arrow?
        # Arrow tool: press on a non-arrow element to begin connecting.
        cleanup_empty_text_selection
        @selected_index = nil
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
        @selected_index = nil
        @drag_mode = DragMode::Drawing
        @draw_start = mouse_world
        @draw_current = mouse_world
      end

    elsif R.mouse_button_down?(R::MouseButton::Left)
      case @drag_mode
      when DragMode::Drawing, DragMode::Connecting
        @draw_current = mouse_world
      when DragMode::Moving
        if (idx = @selected_index) && (sm = @drag_start_mouse) && (sb = @drag_start_bounds)
          dx = mouse_world.x - sm.x
          dy = mouse_world.y - sm.y
          @elements[idx].bounds = R::Rectangle.new(
            x: sb.x + dx, y: sb.y + dy,
            width: sb.width, height: sb.height,
          )
        end
      when DragMode::Resizing
        if (idx = @selected_index) && (h = @active_handle) && (sm = @drag_start_mouse) && (sb = @drag_start_bounds)
          el = @elements[idx]
          min_w, min_h = el.min_size
          el.bounds = apply_resize(h, sb, sm, mouse_world, min_w, min_h)
        end
      end

    elsif R.mouse_button_released?(R::MouseButton::Left)
      if @drag_mode.connecting?
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
            @selected_index = @elements.size - 1
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

    # Backspace: trim the last character (no-op when already empty).
    if R.key_pressed?(R::KeyboardKey::Backspace) || R.key_pressed_repeat?(R::KeyboardKey::Backspace)
      el.handle_backspace
    end

    el.fit_content
  end

  private def handle_delete
    return unless (idx = @selected_index)
    if R.key_pressed?(R::KeyboardKey::Delete) || R.key_pressed_repeat?(R::KeyboardKey::Delete)
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
    @active_tool = ActiveTool::Selection if R.key_pressed?(R::KeyboardKey::S)
    @active_tool = ActiveTool::Rect      if R.key_pressed?(R::KeyboardKey::R)
    @active_tool = ActiveTool::Text      if R.key_pressed?(R::KeyboardKey::T)
    @active_tool = ActiveTool::Arrow     if R.key_pressed?(R::KeyboardKey::A)
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

  private def draw_draft
    return unless (start = @draw_start) && (current = @draw_current)
    if @drag_mode.connecting?
      # Arrow preview: dashed line from source center to current mouse position.
      R.draw_line_ex(start, current, 2.0_f32 / @camera.zoom, DRAFT_STROKE)
    else
      rect = rect_from_points(start, current)
      R.draw_rectangle_rec(rect, DRAFT_FILL)
      R.draw_rectangle_lines_ex(rect, 2.0_f32 / @camera.zoom, DRAFT_STROKE)
    end
  end

  private def draw_selection
    return unless (idx = @selected_index) && idx < @elements.size
    el = @elements[idx]
    thickness = 2.0_f32 / @camera.zoom

    if el.is_a?(ArrowElement)
      # Highlight the arrow line itself instead of drawing a bounding box.
      el.draw_highlighted(SEL_COLOR, 4.0_f32 / @camera.zoom)
      return
    end

    bounds = el.bounds
    R.draw_rectangle_lines_ex(bounds, thickness, SEL_COLOR)

    # Draw resize handles as small squares — only for resizable elements.
    if el.resizable?
      half = (HANDLE_SIZE / 2.0_f32) / @camera.zoom
      hs = HANDLE_SIZE / @camera.zoom
      handle_positions(bounds).each do |(_, center)|
        hr = R::Rectangle.new(x: center.x - half, y: center.y - half, width: hs, height: hs)
        R.draw_rectangle_rec(hr, R::WHITE)
        R.draw_rectangle_lines_ex(hr, 1.5_f32 / @camera.zoom, SEL_COLOR)
      end
    end

    # Blinking text cursor — each element type draws its own cursor.
    el.draw_cursor
  end

  private def rect_from_points(a : R::Vector2, b : R::Vector2) : R::Rectangle
    x = Math.min(a.x, b.x)
    y = Math.min(a.y, b.y)
    w = (a.x - b.x).abs
    h = (a.y - b.y).abs
    R::Rectangle.new(x: x, y: y, width: w, height: h)
  end

  private def draw_grid
    screen_w = R.get_screen_width.to_f32
    screen_h = R.get_screen_height.to_f32
    top_left = R.get_screen_to_world_2d(R::Vector2.new(x: 0.0_f32, y: 0.0_f32), @camera)
    bottom_right = R.get_screen_to_world_2d(R::Vector2.new(x: screen_w, y: screen_h), @camera)

    thickness = 1.0_f32 / @camera.zoom

    start_x = (top_left.x / GRID_SPACING).floor * GRID_SPACING
    x = start_x
    while x <= bottom_right.x
      color = ((x / GRID_SPACING).round.to_i % 5 == 0) ? GRID_COLOR_MAJOR : GRID_COLOR_MINOR
      R.draw_line_ex(
        R::Vector2.new(x: x, y: top_left.y),
        R::Vector2.new(x: x, y: bottom_right.y),
        thickness, color,
      )
      x += GRID_SPACING
    end

    start_y = (top_left.y / GRID_SPACING).floor * GRID_SPACING
    y = start_y
    while y <= bottom_right.y
      color = ((y / GRID_SPACING).round.to_i % 5 == 0) ? GRID_COLOR_MAJOR : GRID_COLOR_MINOR
      R.draw_line_ex(
        R::Vector2.new(x: top_left.x, y: y),
        R::Vector2.new(x: bottom_right.x, y: y),
        thickness, color,
      )
      y += GRID_SPACING
    end

    axis = R::Color.new(r: 180, g: 180, b: 180, a: 255)
    R.draw_line_ex(
      R::Vector2.new(x: -10.0_f32, y: 0.0_f32),
      R::Vector2.new(x: 10.0_f32, y: 0.0_f32),
      thickness, axis,
    )
    R.draw_line_ex(
      R::Vector2.new(x: 0.0_f32, y: -10.0_f32),
      R::Vector2.new(x: 0.0_f32, y: 10.0_f32),
      thickness, axis,
    )
  end
end
