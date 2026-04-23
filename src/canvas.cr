require "json"
require "raylib-cr"
require "./model"
require "./events"
require "./apply"
require "./history"
require "./arrow_layout"
require "./view_state"
require "./element"
require "./persistence"
require "./renderer"
require "./layout_engine"

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

  @renderer      : Renderer = Renderer.new
  @layout_engine : LayoutEngine
  @render_data   : RenderData
  @drag_mode : DragMode = DragMode::None
  @selected_index : Int32? = nil

  # Multi-selection: indices of all selected elements (non-empty only when > 1 selected).
  @selected_indices : Array(Int32) = [] of Int32

  # ── Event-sourcing state ──────────────────────────────────────────────────
  # @model is the authoritative canvas state; @elements is a derived cache.
  @model   : CanvasModel
  @history : HistoryManager

  # UUID-based selection tracking — survives sync_elements_from_model rebuilds.
  @selected_id  : UUID? = nil
  @selected_ids : Array(UUID) = [] of UUID

  # UUID of the element whose text is currently live-edited.
  # TextChangedEvent is emitted on session commit (deselect / move / resize).
  @text_session_id : UUID? = nil

  # Coalescing buffer for consecutive character inserts (word-at-a-time undo).
  # Chars accumulate here until a word boundary is crossed, then one InsertTextEvent is emitted.
  COALESCE_TIMEOUT    =  1.0_f64   # seconds — pause longer than this starts a new word group
  @text_coalesce_id     : UUID?     = nil
  @text_coalesce_pos    : Int32     = 0
  @text_coalesce_text   : String    = ""
  @text_coalesce_bounds : BoundsData = BoundsData.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32)
  @text_coalesce_time   : Float64   = 0.0

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

  @quit_requested : Bool = false

  def quit_requested? : Bool
    @quit_requested
  end

  def initialize(screen_width : Int32, screen_height : Int32)
    @model         = CanvasModel.new
    @history       = HistoryManager.new(@model)
    @elements      = [] of Element
    @layout_engine = LayoutEngine.new(Proc(String, Int32, Int32).new { |t, fs| R.measure_text(t, fs) })
    @render_data   = RenderData.new
    @camera = R::Camera2D.new(
      offset: R::Vector2.new(x: screen_width / 2.0_f32, y: screen_height / 2.0_f32),
      target: R::Vector2.new(x: 0.0_f32, y: 0.0_f32),
      rotation: 0.0_f32,
      zoom: 1.0_f32,
    )
  end

  def save
    File.write(SAVE_FILE, @model.to_json)
  rescue ex
    STDERR.puts "Warning: could not save canvas — #{ex.message}"
  end

  def load
    return unless File.exists?(SAVE_FILE)
    json_str = File.read(SAVE_FILE)
    raw   = JSON.parse(json_str)
    items = (raw["elements"]? || raw["rects"]?).try(&.as_a?) || return

    if items.first?.try { |e| e["bounds"]? }
      # New format: CanvasModel serialises directly with a nested "bounds" object.
      @model = CanvasModel.from_json(json_str)
      @history.reset(@model)
      sync_elements_from_model
    else
      # Legacy format: flat x/y/width/height fields. Load via mirror structs,
      # then immediately save in the new format so the file is migrated.
      load_legacy(items)
      save
    end
  rescue ex
    STDERR.puts "Warning: could not load canvas — #{ex.message}"
  end

  def update
    handle_pan
    handle_zoom
    handle_left_mouse
    handle_text_input
    handle_escape
    handle_delete
    handle_undo_redo
    handle_quit
    handle_tool_switch
    handle_arrow_style_toggle
  end

  def can_undo? : Bool
    @history.can_undo?
  end

  def can_redo? : Bool
    @history.can_redo?
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
    # Arrow bounds come from the layout engine; cull against viewport.
    @elements.each do |e|
      next unless e.is_a?(ArrowElement)
      rd = @render_data[e.id]?
      next unless rd.is_a?(ArrowRenderData)
      b = rd.bounds
      @renderer.draw_element(e, rd) if rd.waypoints.empty? || rects_overlap?(
        R::Rectangle.new(x: b.x, y: b.y, width: b.w, height: b.h), viewport)
    end

    # Non-arrow elements are culled against the viewport.
    @elements.each do |e|
      next if e.is_a?(ArrowElement)
      rd = @render_data[e.id]?
      next unless rd
      b = rd.bounds
      @renderer.draw_element(e, rd) if rects_overlap?(
        R::Rectangle.new(x: b.x, y: b.y, width: b.w, height: b.h), viewport)
    end

    draw_selection
    draw_draft
    R.end_mode_2d
  end

  # ── Event-sourcing helpers ─────────────────────────────────────────────────

  # Apply an event to the model, record it in history, and rebuild @elements.
  # Do NOT call this during an active text session — use commit_text_session_if_active
  # first so the live text is persisted before the sync overwrites the element.
  private def emit(event : CanvasEvent) : Nil
    apply(@model, event)
    @history.push(event)
    sync_elements_from_model
  end

  # Rebuild @elements from @model, preserving selection and arrow back-references.
  # Called after every emit. UUID-based tracking keeps selection stable across rebuilds.
  private def sync_elements_from_model : Nil
    @elements = @model.elements.compact_map do |m|
      case m
      when RectModel
        b = m.bounds
        RectElement.new(
          R::Rectangle.new(x: b.x, y: b.y, width: b.w, height: b.h),
          m.fill.to_raylib, m.stroke.to_raylib, m.stroke_width, m.label, m.id
        ).as(Element)
      when TextModel
        b = m.bounds
        TextElement.new(
          R::Rectangle.new(x: b.x, y: b.y, width: b.w, height: b.h),
          m.text, m.id, m.fixed_width
        ).as(Element)
      when ArrowModel
        style = m.routing_style == "straight" ?
          ArrowElement::RoutingStyle::Straight :
          ArrowElement::RoutingStyle::Orthogonal
        ArrowElement.new(m.from_id, m.to_id, style, m.id).as(Element)
      end
    end

    # Update @selected_index from @selected_id (UUID-stable across rebuilds).
    if (id = @selected_id)
      found = @elements.index { |e| e.id == id }
      @selected_index = found
      if found.nil?
        # Element was deleted — clear all selection state.
        @selected_id     = nil
        @text_session_id = nil
      end
    else
      @selected_index = nil
    end

    # Update @selected_indices from @selected_ids, dropping any deleted elements.
    unless @selected_ids.empty?
      pairs = @selected_ids.compact_map do |id|
        idx = @elements.index { |e| e.id == id }
        idx ? {id, idx} : nil
      end
      @selected_ids     = pairs.map { |(id, _)| id }
      @selected_indices = pairs.map { |(_, idx)| idx }
    end

    @render_data = @layout_engine.layout(@model)
    inject_arrow_waypoints
    inject_text_element_cache
  end

  private def inject_arrow_waypoints : Nil
    @elements.each do |e|
      next unless e.is_a?(ArrowElement)
      rd = @render_data[e.id]?
      next unless rd.is_a?(ArrowRenderData)
      e.cached_waypoints = rd.waypoints.map { |p| R::Vector2.new(x: p[0], y: p[1]) }
    end
  end

  # Injects layout engine output into each TextElement (cached_line_runs,
  # cached_wraps, bounds) so cursor navigation and the Renderer have current data.
  private def inject_text_element_cache : Nil
    @elements.each do |e|
      next unless e.is_a?(TextElement)
      rd = @render_data[e.id]?
      next unless rd.is_a?(TextRenderData)
      e.cached_line_runs = rd.line_runs
      e.cached_wraps     = rd.wraps
      e.bounds = R::Rectangle.new(x: rd.bounds.x, y: rd.bounds.y,
                                   width: rd.bounds.w, height: rd.bounds.h)
    end
  end

  # Updates @render_data for the given moved/resized elements and re-routes any
  # arrows connected to them — called every drag frame so the canvas shows a live
  # preview without touching @model or emitting events.
  private def refresh_drag_preview(moved_ids : Array(UUID)) : Nil
    moved_set = moved_ids.to_set

    # Build a bounds-overrides table from all live non-arrow element positions.
    overrides = {} of UUID => BoundsData
    @elements.each do |el|
      next if el.is_a?(ArrowElement)
      b = el.bounds
      overrides[el.id] = BoundsData.new(b.x, b.y, b.width, b.height)
    end

    # Patch render data for the moved non-arrow elements.
    moved_ids.each do |id|
      rd = @render_data[id]?
      next unless rd
      bd = overrides[id]? || next
      @render_data[id] = case rd
        when RectRenderData
          RectRenderData.new(bd, rd.label_lines)
        when TextRenderData
          # Use the element's cached layout (kept current by refresh_element_layout
          # during resize, or unchanged during move).
          tel = @elements.find { |e| e.id == id }.as?(TextElement)
          TextRenderData.new(bd,
            tel.try(&.cached_line_runs) || rd.line_runs,
            tel ? tel.cached_wraps : rd.wraps)
        else rd
        end
    end

    # Re-route arrows whose endpoints include a moved element.
    @model.elements.each do |m|
      next unless m.is_a?(ArrowModel)
      next unless moved_set.includes?(m.from_id) || moved_set.includes?(m.to_id)
      @render_data[m.id] = @layout_engine.layout_arrow_preview(@model, m, overrides)
    end

    inject_arrow_waypoints
  end

  # Re-runs layout for a single TextElement using its current live state
  # (text/bounds may differ from the model during an active text session).
  # max_auto_width is derived from the current camera zoom so wrapping adapts
  # dynamically without storing it on the element.
  private def refresh_element_layout(el : Element) : Nil
    return unless el.is_a?(TextElement)
    m = @model.find_by_id(el.id)
    return unless m.is_a?(TextModel)
    maw = R.get_screen_width.to_f32 / (2.0_f32 * @camera.zoom)
    tmp = TextModel.new(m.id,
      BoundsData.new(el.bounds.x, el.bounds.y, el.bounds.width, el.bounds.height),
      el.text, el.fixed_width, maw)
    rd = @layout_engine.layout_text_element(tmp)
    el.cached_line_runs = rd.line_runs
    el.cached_wraps     = rd.wraps
    el.bounds = R::Rectangle.new(x: rd.bounds.x, y: rd.bounds.y,
                                  width: rd.bounds.w, height: rd.bounds.h)
  end

  # Flush any live text edits to the model as a TextChangedEvent.
  # Called before structural events that would trigger a sync (which would
  # overwrite the element with the stale model text).
  # Does NOT call sync — the caller's emit will do that.
  # No-op when text is identical to the model (avoids spurious history entries).
  private def commit_text_session_if_active : Nil
    flush_text_coalesce          # emit any buffered chars before comparing to model
    return unless (tid = @text_session_id)
    @text_session_id = nil  # clear first so re-entrant calls are safe
    return unless (idx = @selected_index) && idx < @elements.size
    el = @elements[idx]
    new_text = case el
               when TextElement then el.text
               when RectElement then el.label
               else return
               end
    # Skip if text matches the model's current state.
    model_text = case (m = @model.find_by_id(tid))
                 when TextModel then m.text
                 when RectModel then m.label
                 else ""
                 end
    return if new_text == model_text
    b     = el.bounds
    event = TextChangedEvent.new(tid, new_text, BoundsData.new(b.x, b.y, b.width, b.height))
    apply(@model, event)
    @history.push(event)
  end

  # Load from the old flat-field format (x/y/width/height, no nested bounds).
  # Builds @elements via the *ElementData mirror structs, seeds the model, and
  # resets history. The caller immediately saves to migrate to the new format.
  private def load_legacy(items : Array(JSON::Any)) : Nil
    @elements = items.compact_map do |item|
      type = item["type"]?.try(&.as_s?) || "rect"
      data = item.to_json
      case type
      when "rect"  then RectElementData.from_json(data).to_element.as(Element)
      when "text"  then TextElementData.from_json(data).to_element.as(Element)
      when "arrow" then ArrowElementData.from_json(data).to_element(@elements).as(Element)
      end
    end
    @model = elements_to_model(@elements)
    @history.reset(@model)
    @render_data = @layout_engine.layout(@model)
    inject_arrow_waypoints
  end

  # Build a CanvasModel from the current @elements array.
  # Used after load to seed the model from the legacy persistence format.
  private def elements_to_model(elements : Array(Element)) : CanvasModel
    model = CanvasModel.new
    elements.each do |e|
      case e
      when RectElement
        b = e.bounds
        model.elements << RectModel.new(
          e.id, BoundsData.new(b.x, b.y, b.width, b.height),
          ColorData.new(e.fill), ColorData.new(e.stroke), e.stroke_width, e.label
        )
      when TextElement
        b   = e.bounds
        maw = @model.find_by_id(e.id).try { |m| m.is_a?(TextModel) ? m.max_auto_width : nil }
        model.elements << TextModel.new(
          e.id, BoundsData.new(b.x, b.y, b.width, b.height),
          e.text, e.fixed_width, maw
        )
      when ArrowElement
        model.elements << ArrowModel.new(
          e.id, e.from_id, e.to_id, e.routing_style.to_s.downcase
        )
      end
    end
    model
  end
end

require "./canvas_input"
require "./canvas_drawing"
