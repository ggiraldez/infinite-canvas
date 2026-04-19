require "./spec_helper"

describe "apply" do
  describe CreateRectEvent do
    it "adds a RectModel to the model" do
      m = CanvasModel.new
      id = UUID.random
      ev = CreateRectEvent.new(id, bounds, color, color, 2.0_f32, "hi")
      apply(m, ev)
      m.elements.size.should eq 1
      el = m.find_by_id(id).as(RectModel)
      el.label.should eq "hi"
      el.stroke_width.should eq 2.0_f32
    end
  end

  describe CreateTextEvent do
    it "adds a TextModel to the model" do
      m = CanvasModel.new
      id = UUID.random
      ev = CreateTextEvent.new(id, bounds, "hello", true, 400.0_f32)
      apply(m, ev)
      el = m.find_by_id(id).as(TextModel)
      el.text.should eq "hello"
      el.fixed_width.should be_true
      el.max_auto_width.should eq 400.0_f32
    end
  end

  describe CreateArrowEvent do
    it "adds an ArrowModel when both endpoints exist" do
      from_id = UUID.random
      to_id = UUID.random
      a_id = UUID.random
      m = model_with(rect_model(from_id), rect_model(to_id))
      ev = CreateArrowEvent.new(a_id, from_id, to_id, "straight")
      apply(m, ev)
      m.elements.size.should eq 3
      ar = m.find_by_id(a_id).as(ArrowModel)
      ar.from_id.should eq from_id
      ar.to_id.should eq to_id
      ar.routing_style.should eq "straight"
    end

    it "silently skips when from endpoint is missing" do
      to_id = UUID.random
      m = model_with(rect_model(to_id))
      ev = CreateArrowEvent.new(UUID.random, UUID.random, to_id)
      apply(m, ev)
      m.elements.size.should eq 1
    end

    it "silently skips when to endpoint is missing" do
      from_id = UUID.random
      m = model_with(rect_model(from_id))
      ev = CreateArrowEvent.new(UUID.random, from_id, UUID.random)
      apply(m, ev)
      m.elements.size.should eq 1
    end

    it "silently skips when both endpoints are missing" do
      m = CanvasModel.new
      ev = CreateArrowEvent.new(UUID.random, UUID.random, UUID.random)
      apply(m, ev)
      m.elements.should be_empty
    end
  end

  describe DeleteElementEvent do
    it "removes the element" do
      id = UUID.random
      m = model_with(rect_model(id))
      apply(m, DeleteElementEvent.new(id))
      m.elements.should be_empty
    end

    it "cascades to arrows referencing the deleted element as from_id" do
      r1 = rect_model
      r2 = rect_model
      ar = ArrowModel.new(UUID.random, r1.id, r2.id)
      m = model_with(r1, r2, ar)
      apply(m, DeleteElementEvent.new(r1.id))
      m.find_by_id(ar.id).should be_nil
      m.find_by_id(r2.id).should_not be_nil
    end

    it "cascades to arrows referencing the deleted element as to_id" do
      r1 = rect_model
      r2 = rect_model
      ar = ArrowModel.new(UUID.random, r1.id, r2.id)
      m = model_with(r1, r2, ar)
      apply(m, DeleteElementEvent.new(r2.id))
      m.find_by_id(ar.id).should be_nil
      m.find_by_id(r1.id).should_not be_nil
    end

    it "does not remove unrelated arrows" do
      r1 = rect_model
      r2 = rect_model
      r3 = rect_model
      ar = ArrowModel.new(UUID.random, r2.id, r3.id)
      m = model_with(r1, r2, r3, ar)
      apply(m, DeleteElementEvent.new(r1.id))
      m.find_by_id(ar.id).should_not be_nil
    end

    it "silently ignores unknown ids" do
      m = model_with(rect_model)
      apply(m, DeleteElementEvent.new(UUID.random))
      m.elements.size.should eq 1
    end
  end

  describe MoveElementEvent do
    it "updates element bounds" do
      id = UUID.random
      r = rect_model(id, x: 0.0_f32, y: 0.0_f32, w: 100.0_f32, h: 50.0_f32)
      m = model_with(r)
      new_b = BoundsData.new(10.0_f32, 20.0_f32, 100.0_f32, 50.0_f32)
      apply(m, MoveElementEvent.new(id, new_b))
      el = m.find_by_id(id).not_nil!
      el.bounds.x.should eq 10.0_f32
      el.bounds.y.should eq 20.0_f32
    end

    it "silently ignores unknown ids" do
      m = CanvasModel.new
      apply(m, MoveElementEvent.new(UUID.random, bounds))
      m.elements.should be_empty
    end
  end

  describe MoveMultiEvent do
    it "updates bounds for all listed elements" do
      id1 = UUID.random
      id2 = UUID.random
      m = model_with(rect_model(id1), rect_model(id2))
      b1 = BoundsData.new(5.0_f32, 5.0_f32, 80.0_f32, 40.0_f32)
      b2 = BoundsData.new(200.0_f32, 100.0_f32, 80.0_f32, 40.0_f32)
      apply(m, MoveMultiEvent.new([{id1, b1}, {id2, b2}]))
      m.find_by_id(id1).not_nil!.bounds.x.should eq 5.0_f32
      m.find_by_id(id2).not_nil!.bounds.x.should eq 200.0_f32
    end

    it "skips unknown ids without error" do
      id = UUID.random
      m = model_with(rect_model(id))
      apply(m, MoveMultiEvent.new([{id, bounds(1.0_f32, 2.0_f32)}, {UUID.random, bounds}]))
      m.find_by_id(id).not_nil!.bounds.x.should eq 1.0_f32
    end
  end

  describe ResizeElementEvent do
    it "updates bounds" do
      id = UUID.random
      m = model_with(rect_model(id))
      new_b = BoundsData.new(0.0_f32, 0.0_f32, 300.0_f32, 200.0_f32)
      apply(m, ResizeElementEvent.new(id, new_b))
      m.find_by_id(id).not_nil!.bounds.w.should eq 300.0_f32
    end

    it "locks fixed_width on TextModel" do
      id = UUID.random
      t = TextModel.new(id, bounds, "hi", false)
      m = model_with(t)
      apply(m, ResizeElementEvent.new(id, bounds(0.0_f32, 0.0_f32, 200.0_f32, 50.0_f32)))
      m.find_by_id(id).as(TextModel).fixed_width.should be_true
    end

    it "does not affect fixed_width on RectModel" do
      id = UUID.random
      m = model_with(rect_model(id))
      apply(m, ResizeElementEvent.new(id, bounds))
      # RectModel has no fixed_width; just ensure no error and bounds updated
      m.find_by_id(id).should_not be_nil
    end
  end

  describe TextChangedEvent do
    it "updates text on TextModel" do
      id = UUID.random
      m = model_with(TextModel.new(id, bounds, "old"))
      new_b = BoundsData.new(0.0_f32, 0.0_f32, 120.0_f32, 30.0_f32)
      apply(m, TextChangedEvent.new(id, "new text", new_b))
      el = m.find_by_id(id).as(TextModel)
      el.text.should eq "new text"
      el.bounds.w.should eq 120.0_f32
    end

    it "updates label on RectModel" do
      id = UUID.random
      m = model_with(rect_model(id, "old label"))
      apply(m, TextChangedEvent.new(id, "new label", bounds))
      m.find_by_id(id).as(RectModel).label.should eq "new label"
    end

    it "silently ignores unknown ids" do
      m = CanvasModel.new
      apply(m, TextChangedEvent.new(UUID.random, "x", bounds))
      m.elements.should be_empty
    end
  end

  describe ArrowRoutingChangedEvent do
    it "updates routing style" do
      from_id = UUID.random
      to_id = UUID.random
      a_id = UUID.random
      m = model_with(ArrowModel.new(a_id, from_id, to_id, "orthogonal"))
      apply(m, ArrowRoutingChangedEvent.new(a_id, "straight"))
      m.find_by_id(a_id).as(ArrowModel).routing_style.should eq "straight"
    end

    it "ignores non-arrow elements with that id" do
      id = UUID.random
      m = model_with(rect_model(id))
      apply(m, ArrowRoutingChangedEvent.new(id, "straight"))
      # No error; rect is unchanged
      m.find_by_id(id).should be_a RectModel
    end
  end

  describe InsertTextEvent do
    it "inserts text at position in TextModel" do
      id = UUID.random
      m = model_with(TextModel.new(id, bounds, "helo"))
      apply(m, InsertTextEvent.new(id, 3, "l", bounds))
      m.find_by_id(id).as(TextModel).text.should eq "hello"
    end

    it "inserts at start of TextModel" do
      id = UUID.random
      m = model_with(TextModel.new(id, bounds, "world"))
      apply(m, InsertTextEvent.new(id, 0, "hello ", bounds))
      m.find_by_id(id).as(TextModel).text.should eq "hello world"
    end

    it "inserts at end of TextModel" do
      id = UUID.random
      m = model_with(TextModel.new(id, bounds, "hello"))
      apply(m, InsertTextEvent.new(id, 5, "!", bounds))
      m.find_by_id(id).as(TextModel).text.should eq "hello!"
    end

    it "inserts into RectModel label" do
      id = UUID.random
      m = model_with(rect_model(id, "Box"))
      apply(m, InsertTextEvent.new(id, 3, " A", bounds))
      m.find_by_id(id).as(RectModel).label.should eq "Box A"
    end

    it "updates bounds" do
      id = UUID.random
      m = model_with(TextModel.new(id, bounds, "hi"))
      new_b = BoundsData.new(0.0_f32, 0.0_f32, 150.0_f32, 30.0_f32)
      apply(m, InsertTextEvent.new(id, 2, "!", new_b))
      m.find_by_id(id).not_nil!.bounds.w.should eq 150.0_f32
    end

    it "handles unicode characters" do
      id = UUID.random
      m = model_with(TextModel.new(id, bounds, "hllo"))
      apply(m, InsertTextEvent.new(id, 1, "é", bounds))
      m.find_by_id(id).as(TextModel).text.should eq "héllo"
    end
  end

  describe DeleteTextEvent do
    it "deletes a range from TextModel" do
      id = UUID.random
      m = model_with(TextModel.new(id, bounds, "hello world"))
      apply(m, DeleteTextEvent.new(id, 5, 6, bounds))
      m.find_by_id(id).as(TextModel).text.should eq "hello"
    end

    it "deletes a single char from TextModel" do
      id = UUID.random
      m = model_with(TextModel.new(id, bounds, "helllo"))
      apply(m, DeleteTextEvent.new(id, 3, 1, bounds))
      m.find_by_id(id).as(TextModel).text.should eq "hello"
    end

    it "deletes from RectModel label" do
      id = UUID.random
      m = model_with(rect_model(id, "Box A"))
      apply(m, DeleteTextEvent.new(id, 3, 2, bounds))
      m.find_by_id(id).as(RectModel).label.should eq "Box"
    end

    it "updates bounds" do
      id = UUID.random
      m = model_with(TextModel.new(id, bounds, "hello world"))
      new_b = BoundsData.new(0.0_f32, 0.0_f32, 60.0_f32, 30.0_f32)
      apply(m, DeleteTextEvent.new(id, 5, 6, new_b))
      m.find_by_id(id).not_nil!.bounds.w.should eq 60.0_f32
    end

    it "silently ignores unknown ids" do
      m = CanvasModel.new
      apply(m, DeleteTextEvent.new(UUID.random, 0, 1, bounds))
      m.elements.should be_empty
    end
  end

  it "returns the model" do
    m = CanvasModel.new
    result = apply(m, CreateRectEvent.new(UUID.random, bounds, color, color, 1.0_f32))
    result.should be m
  end
end
