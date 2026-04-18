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
  # new_bounds captures the post-fit_content size at emission time.
  property id : UUID
  property new_text : String
  property new_bounds : BoundsData

  def initialize(@id : UUID, @new_text : String, @new_bounds : BoundsData); end
end

class ArrowRoutingChangedEvent < CanvasEvent
  property id : UUID
  property new_style : String

  def initialize(@id : UUID, @new_style : String); end
end
