require "./spec_helper"

describe BoundsData do
  it "stores coordinates" do
    b = BoundsData.new(1.0_f32, 2.0_f32, 30.0_f32, 40.0_f32)
    b.x.should eq 1.0_f32
    b.y.should eq 2.0_f32
    b.w.should eq 30.0_f32
    b.h.should eq 40.0_f32
  end

  it "roundtrips through JSON" do
    b = BoundsData.new(5.0_f32, 6.0_f32, 7.0_f32, 8.0_f32)
    b2 = BoundsData.from_json(b.to_json)
    b2.x.should eq b.x
    b2.y.should eq b.y
    b2.w.should eq b.w
    b2.h.should eq b.h
  end
end

describe ColorData do
  it "stores RGBA channels" do
    c = ColorData.new(10_u8, 20_u8, 30_u8, 255_u8)
    c.r.should eq 10_u8
    c.g.should eq 20_u8
    c.b.should eq 30_u8
    c.a.should eq 255_u8
  end

  it "roundtrips through JSON" do
    c = ColorData.new(1_u8, 2_u8, 3_u8, 4_u8)
    c2 = ColorData.from_json(c.to_json)
    c2.r.should eq c.r
    c2.g.should eq c.g
    c2.b.should eq c.b
    c2.a.should eq c.a
  end
end

describe RectModel do
  it "stores all fields" do
    id = UUID.random
    r = RectModel.new(id, bounds(1.0_f32, 2.0_f32, 80.0_f32, 60.0_f32),
      color(255_u8, 0_u8, 0_u8, 200_u8),
      color(0_u8, 0_u8, 255_u8, 255_u8),
      3.0_f32, "hello")
    r.id.should eq id
    r.label.should eq "hello"
    r.stroke_width.should eq 3.0_f32
    r.type.should eq "rect"
  end

  it "roundtrips through JSON as ElementModel" do
    r = rect_model(label: "test")
    json = r.to_json
    parsed = ElementModel.from_json(json)
    parsed.should be_a RectModel
    (parsed.as(RectModel)).label.should eq "test"
  end
end

describe TextModel do
  it "defaults to auto-width mode" do
    t = TextModel.new(UUID.random, bounds, "hi")
    t.fixed_width.should be_false
    t.max_auto_width.should be_nil
    t.type.should eq "text"
  end

  it "stores optional max_auto_width" do
    t = TextModel.new(UUID.random, bounds, "hi", false, 300.0_f32)
    t.max_auto_width.should eq 300.0_f32
  end

  it "omits max_auto_width from JSON when nil" do
    t = TextModel.new(UUID.random, bounds, "hi")
    t.to_json.should_not contain("max_auto_width")
  end

  it "roundtrips through JSON as ElementModel" do
    t = TextModel.new(UUID.random, bounds, "world", true, 200.0_f32)
    parsed = ElementModel.from_json(t.to_json).as(TextModel)
    parsed.text.should eq "world"
    parsed.fixed_width.should be_true
    parsed.max_auto_width.should eq 200.0_f32
  end
end

describe ArrowModel do
  it "starts with zeroed bounds" do
    a = ArrowModel.new(UUID.random, UUID.random, UUID.random)
    a.bounds.x.should eq 0.0_f32
    a.bounds.y.should eq 0.0_f32
    a.bounds.w.should eq 0.0_f32
    a.bounds.h.should eq 0.0_f32
    a.type.should eq "arrow"
  end

  it "defaults to orthogonal routing" do
    a = ArrowModel.new(UUID.random, UUID.random, UUID.random)
    a.routing_style.should eq "orthogonal"
  end

  it "roundtrips through JSON as ElementModel" do
    from_id = UUID.random
    to_id = UUID.random
    a = ArrowModel.new(UUID.random, from_id, to_id, "straight")
    parsed = ElementModel.from_json(a.to_json).as(ArrowModel)
    parsed.from_id.should eq from_id
    parsed.to_id.should eq to_id
    parsed.routing_style.should eq "straight"
  end
end

describe CanvasModel do
  it "starts empty" do
    m = CanvasModel.new
    m.elements.should be_empty
  end

  it "finds elements by id" do
    id = UUID.random
    r = rect_model(id)
    m = model_with(r)
    m.find_by_id(id).should eq r
  end

  it "returns nil for unknown id" do
    m = CanvasModel.new
    m.find_by_id(UUID.random).should be_nil
  end

  it "roundtrips through JSON preserving all element types" do
    r_id = UUID.random
    t_id = UUID.random
    from_id = UUID.random
    to_id = UUID.random
    a_id = UUID.random

    m = model_with(
      rect_model(r_id, "lbl"),
      text_model(t_id, "txt"),
      ArrowModel.new(a_id, from_id, to_id)
    )

    m2 = CanvasModel.from_json(m.to_json)
    m2.elements.size.should eq 3
    m2.find_by_id(r_id).should be_a RectModel
    m2.find_by_id(t_id).should be_a TextModel
    m2.find_by_id(a_id).should be_a ArrowModel

    m2.find_by_id(r_id).as(RectModel).label.should eq "lbl"
    m2.find_by_id(t_id).as(TextModel).text.should eq "txt"
    m2.find_by_id(a_id).as(ArrowModel).from_id.should eq from_id
  end
end
