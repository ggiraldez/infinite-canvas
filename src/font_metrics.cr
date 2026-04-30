abstract class FontMetrics
  abstract def measure(text : String) : Int32
  abstract def size : Int32
  abstract def spacing : Float32
end
