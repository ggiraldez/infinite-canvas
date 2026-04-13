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
  SAVE_FILE        = "canvas.json"

  enum DragMode
    None
    Drawing
    Moving
    Resizing
  end

  enum Handle
    NW; N; NE; E; SE; S; SW; W
  end

  getter elements : Array(Element)
  getter camera : R::Camera2D

  @drag_mode : DragMode = DragMode::None
  @selected_index : Int32? = nil

  # Drawing state
  @draw_start : R::Vector2?
  @draw_current : R::Vector2?

  # Move / resize state
  @drag_start_mouse : R::Vector2?
  @drag_start_bounds : R::Rectangle?
  @active_handle : Handle?

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
    rects = @elements.compact_map { |e| RectElementData.new(e) if e.is_a?(RectElement) }
    File.write(SAVE_FILE, CanvasSaveData.new(rects).to_json)
  rescue ex
    STDERR.puts "Warning: could not save canvas — #{ex.message}"
  end

  def load
    return unless File.exists?(SAVE_FILE)
    data = CanvasSaveData.from_json(File.read(SAVE_FILE))
    @elements = data.rects.map(&.to_element.as(Element))
  rescue ex
    STDERR.puts "Warning: could not load canvas — #{ex.message}"
  end

  def update
    handle_pan
    handle_zoom
    handle_left_mouse
    handle_delete
  end

  def draw
    R.begin_mode_2d(@camera)
    draw_grid
    @elements.each(&.draw)
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

    zoom_factor = 1.0_f32 + wheel * 0.1_f32
    new_zoom = (@camera.zoom * zoom_factor).clamp(0.1_f32, 10.0_f32)
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
      if (handle = hit_test_handles(mouse_world))
        # Begin resize of the already-selected element.
        idx = @selected_index.not_nil!
        @drag_mode = DragMode::Resizing
        @active_handle = handle
        @drag_start_mouse = mouse_world
        @drag_start_bounds = @elements[idx].bounds
      elsif (idx = hit_test_element(mouse_world))
        # Select element and begin move.
        @selected_index = idx
        @drag_mode = DragMode::Moving
        @drag_start_mouse = mouse_world
        @drag_start_bounds = @elements[idx].bounds
      else
        # Click on empty space: deselect and start drawing.
        @selected_index = nil
        @drag_mode = DragMode::Drawing
        @draw_start = mouse_world
        @draw_current = mouse_world
      end

    elsif R.mouse_button_down?(R::MouseButton::Left)
      case @drag_mode
      when DragMode::Drawing
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
          @elements[idx].bounds = apply_resize(h, sb, sm, mouse_world)
        end
      end

    elsif R.mouse_button_released?(R::MouseButton::Left)
      if @drag_mode.drawing?
        if (start = @draw_start) && (current = @draw_current)
          rect = rect_from_points(start, current)
          if rect.width >= 4.0_f32 && rect.height >= 4.0_f32
            @elements << RectElement.new(rect)
            @selected_index = @elements.size - 1
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

  private def handle_delete
    return unless (idx = @selected_index)
    if R.key_pressed?(R::KeyboardKey::Delete) || R.key_pressed?(R::KeyboardKey::Backspace)
      @elements.delete_at(idx)
      @selected_index = nil
    end
  end

  # Returns the index of the topmost element under *mouse_world*, or nil.
  private def hit_test_element(mouse_world : R::Vector2) : Int32?
    (@elements.size - 1).downto(0) do |i|
      return i if @elements[i].contains?(mouse_world)
    end
    nil
  end

  # Returns which resize handle the mouse is over, or nil.
  private def hit_test_handles(mouse_world : R::Vector2) : Handle?
    return nil unless (idx = @selected_index)
    return nil unless idx < @elements.size
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
  private def apply_resize(handle : Handle, orig : R::Rectangle, sm : R::Vector2, mouse : R::Vector2) : R::Rectangle
    dx = mouse.x - sm.x
    dy = mouse.y - sm.y
    x, y, w, h = orig.x, orig.y, orig.width, orig.height
    min = 4.0_f32

    # Left edge (NW, W, SW)
    if handle.nw? || handle.w? || handle.sw?
      new_w = orig.width - dx
      if new_w >= min
        x = orig.x + dx
        w = new_w
      end
    end
    # Right edge (NE, E, SE)
    if handle.ne? || handle.e? || handle.se?
      new_w = orig.width + dx
      w = new_w if new_w >= min
    end
    # Top edge (NW, N, NE)
    if handle.nw? || handle.n? || handle.ne?
      new_h = orig.height - dy
      if new_h >= min
        y = orig.y + dy
        h = new_h
      end
    end
    # Bottom edge (SW, S, SE)
    if handle.sw? || handle.s? || handle.se?
      new_h = orig.height + dy
      h = new_h if new_h >= min
    end

    R::Rectangle.new(x: x, y: y, width: w, height: h)
  end

  private def draw_draft
    return unless (start = @draw_start) && (current = @draw_current)
    rect = rect_from_points(start, current)
    R.draw_rectangle_rec(rect, DRAFT_FILL)
    R.draw_rectangle_lines_ex(rect, 2.0_f32 / @camera.zoom, DRAFT_STROKE)
  end

  private def draw_selection
    return unless (idx = @selected_index) && idx < @elements.size
    bounds = @elements[idx].bounds
    thickness = 2.0_f32 / @camera.zoom

    R.draw_rectangle_lines_ex(bounds, thickness, SEL_COLOR)

    # Draw resize handles as small squares.
    half = (HANDLE_SIZE / 2.0_f32) / @camera.zoom
    hs = HANDLE_SIZE / @camera.zoom
    handle_positions(bounds).each do |(_, center)|
      hr = R::Rectangle.new(x: center.x - half, y: center.y - half, width: hs, height: hs)
      R.draw_rectangle_rec(hr, R::WHITE)
      R.draw_rectangle_lines_ex(hr, 1.5_f32 / @camera.zoom, SEL_COLOR)
    end
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
