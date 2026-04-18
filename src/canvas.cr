require "json"
require "raylib-cr"
require "./model"
require "./events"
require "./apply"
require "./history"
require "./layout"
require "./element"
require "./persistence"

# Infinite canvas: owns the Camera2D, the element list, and input handling.
class Canvas
  GRID_SPACING     =  50.0_f32
  SNAP_GRID        =  10.0_f32 # snap resolution: 5× finer than the drawn grid
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
  SEL_DRAG_FILL    = R::Color.new(r: 0, g: 120, b: 255, a: 25)
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
    Selecting   # Selection tool: rubber-band drag over empty space
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

  # Multi-selection: indices of all selected elements (non-empty only when > 1 selected).
  @selected_indices : Array(Int32) = [] of Int32

  # Drawing state
  @draw_start : R::Vector2?
  @draw_current : R::Vector2?

  # Move / resize state
  @drag_start_mouse : R::Vector2?
  @drag_start_bounds : R::Rectangle?
  @active_handle : Handle?

  # Starting bounds for all elements during a multi-element move.
  @multi_drag_starts : Array(R::Rectangle)?

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

    # Compute the visible world-space rectangle for culling.
    sw = R.get_screen_width.to_f32
    sh = R.get_screen_height.to_f32
    tl = R.get_screen_to_world_2d(R::Vector2.new(x: 0.0_f32, y: 0.0_f32), @camera)
    br = R.get_screen_to_world_2d(R::Vector2.new(x: sw, y: sh), @camera)
    viewport = R::Rectangle.new(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)

    # Arrows first so they appear behind shapes and text.
    # Arrow bounds start at (0,0,0,0) and are only updated during draw, so they
    # are always drawn regardless of viewport (they are cheap line primitives).
    @elements.each { |e| e.draw if e.is_a?(ArrowElement) }

    # Non-arrow elements are culled against the viewport.
    @elements.each do |e|
      next if e.is_a?(ArrowElement)
      e.draw if rects_overlap?(e.bounds, viewport)
    end

    draw_selection
    draw_draft
    R.end_mode_2d
  end
end

require "./canvas_input"
require "./canvas_drawing"
