require "uuid"

# Pure canvas data model — zero Raylib dependency.
# All coordinates and sizes are plain Float32.
# Serialization and Raylib conversions are added in persistence.cr via reopen.

struct BoundsData
  property x : Float32
  property y : Float32
  property w : Float32
  property h : Float32

  def initialize(@x : Float32, @y : Float32, @w : Float32, @h : Float32)
  end
end

struct ColorData
  property r : UInt8
  property g : UInt8
  property b : UInt8
  property a : UInt8

  def initialize(@r : UInt8, @g : UInt8, @b : UInt8, @a : UInt8)
  end
end

# Abstract base for all canvas elements. Subclasses own their own fields;
# this class owns only the identity and bounding box.
abstract class ElementModel
  property id : UUID
  property bounds : BoundsData

  def initialize(@id : UUID, @bounds : BoundsData)
  end
end

class RectModel < ElementModel
  property fill : ColorData
  property stroke : ColorData
  property stroke_width : Float32
  property label : String

  def initialize(@id : UUID, @bounds : BoundsData,
                 @fill : ColorData, @stroke : ColorData,
                 @stroke_width : Float32, @label : String)
    super(@id, @bounds)
  end
end

class TextModel < ElementModel
  property text : String
  property fixed_width : Bool
  property max_auto_width : Float32?

  def initialize(@id : UUID, @bounds : BoundsData, @text : String,
                 @fixed_width : Bool = false, @max_auto_width : Float32? = nil)
    super(@id, @bounds)
  end
end

class ArrowModel < ElementModel
  property from_id : UUID
  property to_id : UUID
  property routing_style : String # "orthogonal" | "straight"

  # Arrows have no meaningful static bounds; their extent is derived from
  # the path computed during layout. Bounds start zeroed and are unused for culling.
  def initialize(@id : UUID, @from_id : UUID, @to_id : UUID,
                 @routing_style : String = "orthogonal")
    super(@id, BoundsData.new(0.0_f32, 0.0_f32, 0.0_f32, 0.0_f32))
  end
end

class CanvasModel
  property elements : Array(ElementModel)

  def initialize
    @elements = [] of ElementModel
  end

  def find_by_id(id : UUID) : ElementModel?
    @elements.find { |e| e.id == id }
  end
end
