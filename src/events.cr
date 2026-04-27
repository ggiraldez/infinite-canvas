require "uuid"
require "./model"

# Base class for all canvas mutation events.
# Events capture *final state* (not deltas) so replay is always deterministic.
# View-derived values (e.g. max_auto_width from screen size / zoom) must be
# resolved and stored in the event at emission time, not recomputed on replay.
abstract class CanvasEvent; end

class CreateRectEvent < CanvasEvent
  property id : UUID
  property bounds : BoundsData
  property fill : ColorData
  property stroke : ColorData
  property stroke_width : Float32
  property label : String

  def initialize(@id : UUID, @bounds : BoundsData,
                 @fill : ColorData, @stroke : ColorData,
                 @stroke_width : Float32, @label : String = "")
  end
end

class CreateTextEvent < CanvasEvent
  property id : UUID
  property bounds : BoundsData
  property text : String
  property fixed_width : Bool
  property max_auto_width : Float32?

  def initialize(@id : UUID, @bounds : BoundsData, @text : String = "",
                 @fixed_width : Bool = false, @max_auto_width : Float32? = nil)
  end
end

class CreateArrowEvent < CanvasEvent
  property id : UUID
  property from_id : UUID
  property to_id : UUID
  property routing_style : String

  def initialize(@id : UUID, @from_id : UUID, @to_id : UUID,
                 @routing_style : String = "orthogonal")
  end
end

class DeleteElementEvent < CanvasEvent
  # Cascaded arrow removal is derived in apply() — not stored here.
  property id : UUID

  def initialize(@id : UUID); end
end

class MoveElementEvent < CanvasEvent
  property id : UUID
  property new_bounds : BoundsData

  def initialize(@id : UUID, @new_bounds : BoundsData); end
end

class MoveMultiEvent < CanvasEvent
  property moves : Array(Tuple(UUID, BoundsData))

  def initialize(@moves : Array(Tuple(UUID, BoundsData))); end
end

class ResizeElementEvent < CanvasEvent
  property id : UUID
  property new_bounds : BoundsData

  def initialize(@id : UUID, @new_bounds : BoundsData); end
end

class TextChangedEvent < CanvasEvent
  # Applies to both TextModel (text field) and RectModel (label field).
  # new_bounds captures the post-layout size at emission time.
  # cursor_before: char offset of cursor before this event (used to restore position on undo).
  property id : UUID
  property new_text : String
  property new_bounds : BoundsData
  property cursor_before : Int32

  def initialize(@id : UUID, @new_text : String, @new_bounds : BoundsData, @cursor_before : Int32 = 0); end
end

class ChangeRectColorEvent < CanvasEvent
  property id : UUID
  property fill : ColorData
  property stroke : ColorData
  property label_color : ColorData

  def initialize(@id : UUID, @fill : ColorData, @stroke : ColorData, @label_color : ColorData); end
end

class ArrowRoutingChangedEvent < CanvasEvent
  property id : UUID
  property new_style : String

  def initialize(@id : UUID, @new_style : String); end
end

# Fine-grained text events for per-word undo within a text session.
# Emitted immediately during editing (no sync); model stays in step with the element.

class InsertTextEvent < CanvasEvent
  property id : UUID
  property position : Int32       # char offset where text was inserted
  property text : String          # inserted text (1 char normally; multi for paste)
  property new_bounds : BoundsData

  def initialize(@id : UUID, @position : Int32, @text : String, @new_bounds : BoundsData); end
end

class DeleteTextEvent < CanvasEvent
  property id : UUID
  property start : Int32          # char offset of first deleted char
  property length : Int32         # number of chars deleted
  property new_bounds : BoundsData
  property cursor_before : Int32  # cursor position before the delete (for undo restoration)

  def initialize(@id : UUID, @start : Int32, @length : Int32, @new_bounds : BoundsData, @cursor_before : Int32 = 0); end
end
