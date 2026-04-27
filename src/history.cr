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

  def last_event : CanvasEvent?
    @event_log.last?
  end

  def last_redo_event : CanvasEvent?
    @redo_stack.last?
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

  # ── Serialization ─────────────────────────────────────────────────────────

  private def serialize(model : CanvasModel) : String
    model.to_json
  end

  private def deserialize(json_str : String) : CanvasModel
    CanvasModel.from_json(json_str)
  rescue ex
    STDERR.puts "Warning: could not deserialize checkpoint — #{ex.message}"
    CanvasModel.new
  end
end
