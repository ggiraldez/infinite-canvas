require "json"
require "uuid"
require "./model"
require "./events"
require "./apply"

# Checkpoint-based undo/redo using the event log.
#
# Strategy (Phase 3 — single checkpoint):
#   State  = checkpoint (serialized CanvasModel) + event_log (events since checkpoint)
#   Undo   = pop last event → redo_stack, replay(checkpoint, event_log)
#   Redo   = pop from redo_stack → event_log, replay(checkpoint, event_log)
#   Evict  = when event_log exceeds MAX_UNDO, advance checkpoint by one event
#            (re-serialize so checkpoint always encodes the full history)
#
# Phase 8 will generalise to multiple checkpoints for O(1) undo at depth.
class HistoryManager
  MAX_UNDO = 100

  @checkpoint : String
  @event_log : Array(CanvasEvent)
  @redo_stack : Array(CanvasEvent)

  def initialize(initial_model : CanvasModel = CanvasModel.new)
    @checkpoint = serialize(initial_model)
    @event_log  = [] of CanvasEvent
    @redo_stack = [] of CanvasEvent
  end

  # Record a new event. Clears the redo stack.
  def push(event : CanvasEvent) : Nil
    @event_log << event
    @redo_stack.clear
    evict_if_needed
  end

  # Undo the last event. Returns the restored model, or nil if nothing to undo.
  def undo : CanvasModel?
    return nil if @event_log.empty?
    @redo_stack << @event_log.pop
    restore
  end

  # Redo the last undone event. Returns the restored model, or nil if nothing to redo.
  def redo : CanvasModel?
    return nil if @redo_stack.empty?
    @event_log << @redo_stack.pop
    restore
  end

  def can_undo? : Bool
    !@event_log.empty?
  end

  def can_redo? : Bool
    !@redo_stack.empty?
  end

  # Reset history to a new base model (call after loading from disk).
  def reset(model : CanvasModel) : Nil
    @checkpoint = serialize(model)
    @event_log.clear
    @redo_stack.clear
  end

  # ── Replay ────────────────────────────────────────────────────────────────

  private def restore : CanvasModel
    model = deserialize(@checkpoint)
    @event_log.each { |e| apply(model, e) }
    model
  end

  # When the log is full, absorb the oldest event into the checkpoint so the
  # log never grows beyond MAX_UNDO entries.
  private def evict_if_needed : Nil
    while @event_log.size > MAX_UNDO
      base = deserialize(@checkpoint)
      apply(base, @event_log.first)
      @checkpoint = serialize(base)
      @event_log.shift
    end
  end

  # ── Serialization (temporary — replaced by JSON::Serializable in Phase 7) ─

  private def serialize(model : CanvasModel) : String
    JSON.build do |json|
      json.object do
        json.field "elements" do
          json.array do
            model.elements.each do |e|
              json.object do
                case e
                when RectModel
                  json.field "type", "rect"
                  json.field "id", e.id.to_s
                  write_bounds(json, e.bounds)
                  json.field "fill"   { write_color(json, e.fill) }
                  json.field "stroke" { write_color(json, e.stroke) }
                  json.field "stroke_width", e.stroke_width
                  json.field "label", e.label
                when TextModel
                  json.field "type", "text"
                  json.field "id", e.id.to_s
                  write_bounds(json, e.bounds)
                  json.field "text", e.text
                  json.field "fixed_width", e.fixed_width
                  if (maw = e.max_auto_width)
                    json.field "max_auto_width", maw
                  end
                when ArrowModel
                  json.field "type", "arrow"
                  json.field "id", e.id.to_s
                  json.field "from_id", e.from_id.to_s
                  json.field "to_id", e.to_id.to_s
                  json.field "routing_style", e.routing_style
                end
              end
            end
          end
        end
      end
    end
  end

  private def write_bounds(json : JSON::Builder, b : BoundsData) : Nil
    json.field "x", b.x
    json.field "y", b.y
    json.field "w", b.w
    json.field "h", b.h
  end

  private def write_color(json : JSON::Builder, c : ColorData) : Nil
    json.object do
      json.field "r", c.r
      json.field "g", c.g
      json.field "b", c.b
      json.field "a", c.a
    end
  end

  # ── Deserialization ────────────────────────────────────────────────────────

  private def deserialize(json_str : String) : CanvasModel
    model = CanvasModel.new
    raw   = JSON.parse(json_str)
    items = raw["elements"]?.try(&.as_a?)
    return model unless items

    items.each do |item|
      type   = item["type"]?.try(&.as_s?) || next
      id_str = item["id"]?.try(&.as_s?)   || next
      id     = UUID.new(id_str)

      case type
      when "rect"
        bounds = read_bounds(item)
        fill   = item["fill"]?.try   { |v| read_color(v) } || ColorData.new(90_u8, 140_u8, 220_u8, 200_u8)
        stroke = item["stroke"]?.try { |v| read_color(v) } || ColorData.new(30_u8, 60_u8, 120_u8, 255_u8)
        sw     = item["stroke_width"]?.try { |v| as_f32(v) } || 2.0_f32
        label  = item["label"]?.try(&.as_s?) || ""
        model.elements << RectModel.new(id, bounds, fill, stroke, sw, label)

      when "text"
        bounds     = read_bounds(item)
        text       = item["text"]?.try(&.as_s?) || ""
        fixed      = item["fixed_width"]?.try(&.as_bool?) || false
        max_auto_w = item["max_auto_width"]?.try { |v| as_f32(v) }
        model.elements << TextModel.new(id, bounds, text, fixed, max_auto_w)

      when "arrow"
        from_str = item["from_id"]?.try(&.as_s?) || next
        to_str   = item["to_id"]?.try(&.as_s?)   || next
        routing  = item["routing_style"]?.try(&.as_s?) || "orthogonal"
        model.elements << ArrowModel.new(id, UUID.new(from_str), UUID.new(to_str), routing)
      end
    end

    model
  rescue ex
    STDERR.puts "Warning: could not deserialize checkpoint — #{ex.message}"
    CanvasModel.new
  end

  private def read_bounds(item : JSON::Any) : BoundsData
    BoundsData.new(
      item["x"]?.try { |v| as_f32(v) } || 0.0_f32,
      item["y"]?.try { |v| as_f32(v) } || 0.0_f32,
      item["w"]?.try { |v| as_f32(v) } || 0.0_f32,
      item["h"]?.try { |v| as_f32(v) } || 0.0_f32
    )
  end

  private def read_color(item : JSON::Any) : ColorData
    ColorData.new(
      item["r"]?.try { |v| as_u8(v) } || 0_u8,
      item["g"]?.try { |v| as_u8(v) } || 0_u8,
      item["b"]?.try { |v| as_u8(v) } || 0_u8,
      item["a"]?.try { |v| as_u8(v) } || 255_u8
    )
  end

  # Handles both JSON float and integer values robustly.
  private def as_f32(v : JSON::Any) : Float32
    (v.as_f? || v.as_i64?.try(&.to_f64) || 0.0_f64).to_f32
  end

  private def as_u8(v : JSON::Any) : UInt8
    (v.as_i64? || v.as_f?.try(&.to_i64) || 0_i64).to_u8
  end
end
