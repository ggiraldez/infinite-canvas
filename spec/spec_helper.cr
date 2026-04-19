require "spec"
require "../src/model"
require "../src/events"
require "../src/apply"
require "../src/history"

# Helpers for building test fixtures without Raylib types.

def bounds(x = 0.0_f32, y = 0.0_f32, w = 100.0_f32, h = 50.0_f32)
  BoundsData.new(x, y, w, h)
end

def color(r : UInt8 = 255_u8, g : UInt8 = 0_u8, b : UInt8 = 0_u8, a : UInt8 = 255_u8)
  ColorData.new(r, g, b, a)
end

def rect_model(id : UUID = UUID.random, label = "", x = 0.0_f32, y = 0.0_f32, w = 100.0_f32, h = 50.0_f32)
  RectModel.new(id, bounds(x, y, w, h), color, color(0, 0, 255), 2.0_f32, label)
end

def text_model(id : UUID = UUID.random, text = "hello")
  TextModel.new(id, bounds, text)
end

def arrow_model(id : UUID = UUID.random, from_id : UUID = UUID.random, to_id : UUID = UUID.random)
  ArrowModel.new(id, from_id, to_id)
end

def model_with(*elements)
  m = CanvasModel.new
  elements.each { |e| m.elements << e }
  m
end
