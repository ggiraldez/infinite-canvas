require "json"
require "uuid"

# JSON::Serializable uses `T.new(pull)` for deserialization. UUID doesn't
# provide that constructor, so we add it here once for all serialisable models.
struct UUID
  def self.new(pull : JSON::PullParser)
    new(pull.read_string)
  end

  def to_json(json : JSON::Builder)
    json.string(to_s)
  end
end

# Pure canvas data model — zero Raylib dependency.
# All coordinates and sizes are plain Float32.
# Raylib conversions are added in persistence.cr via reopen.

struct BoundsData
  include JSON::Serializable

  property x : Float32
  property y : Float32
  property w : Float32
  property h : Float32

  def initialize(@x : Float32, @y : Float32, @w : Float32, @h : Float32)
  end
end

struct ColorData
  include JSON::Serializable

  property r : UInt8
  property g : UInt8
  property b : UInt8
  property a : UInt8

  def initialize(@r : UInt8, @g : UInt8, @b : UInt8, @a : UInt8)
  end
end

# Abstract base for all canvas elements.
# use_json_discriminator reads the "type" field to dispatch to the right subclass.
abstract class ElementModel
  include JSON::Serializable

  use_json_discriminator "type", {rect: RectModel, text: TextModel, arrow: ArrowModel}

  property id : UUID
  property bounds : BoundsData

  def initialize(@id : UUID, @bounds : BoundsData)
  end
end

class RectModel < ElementModel
  property type : String = "rect"
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
  property type : String = "text"
  property text : String
  property fixed_width : Bool
  @[JSON::Field(emit_null: false)]
  property max_auto_width : Float32?

  def initialize(@id : UUID, @bounds : BoundsData, @text : String,
                 @fixed_width : Bool = false, @max_auto_width : Float32? = nil)
    super(@id, @bounds)
  end
end

class ArrowModel < ElementModel
  property type : String = "arrow"
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
  include JSON::Serializable

  property elements : Array(ElementModel)

  def initialize
    @elements = [] of ElementModel
  end

  def find_by_id(id : UUID) : ElementModel?
    @elements.find { |e| e.id == id }
  end
end
