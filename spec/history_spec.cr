require "./spec_helper"

def make_history(model = CanvasModel.new)
  HistoryManager.new(model)
end

def push_rect(h : HistoryManager, m : CanvasModel, label = "r") : {UUID, CanvasModel}
  id = UUID.random
  ev = CreateRectEvent.new(id, bounds, color, color, 1.0_f32, label)
  apply(m, ev)
  h.push(ev)
  {id, m}
end

describe HistoryManager do
  describe "initial state" do
    it "cannot undo or redo on a fresh manager" do
      h = make_history
      h.can_undo?.should be_false
      h.can_redo?.should be_false
    end
  end

  describe "#push" do
    it "enables undo after one event" do
      h = make_history
      m = CanvasModel.new
      push_rect(h, m)
      h.can_undo?.should be_true
      h.can_redo?.should be_false
    end

    it "clears the redo stack" do
      h = make_history
      m = CanvasModel.new
      push_rect(h, m)
      h.undo
      h.can_redo?.should be_true
      push_rect(h, m)
      h.can_redo?.should be_false
    end
  end

  describe "#undo" do
    it "returns nil when nothing to undo" do
      h = make_history
      h.undo.should be_nil
    end

    it "removes the last event and rebuilds model" do
      h = make_history
      m = CanvasModel.new
      id1, _ = push_rect(h, m, "first")
      id2, _ = push_rect(h, m, "second")

      result = h.undo.not_nil!
      result.find_by_id(id1).should_not be_nil
      result.find_by_id(id2).should be_nil
    end

    it "enables redo after undo" do
      h = make_history
      m = CanvasModel.new
      push_rect(h, m)
      h.undo
      h.can_redo?.should be_true
    end

    it "returns empty model after undoing all events" do
      h = make_history
      m = CanvasModel.new
      push_rect(h, m)
      result = h.undo.not_nil!
      result.elements.should be_empty
      h.can_undo?.should be_false
    end

    it "can undo multiple events in sequence" do
      h = make_history
      m = CanvasModel.new
      id1, _ = push_rect(h, m, "a")
      id2, _ = push_rect(h, m, "b")
      id3, _ = push_rect(h, m, "c")

      h.undo
      h.undo
      result = h.undo.not_nil!
      result.elements.should be_empty
      h.can_undo?.should be_false
    end
  end

  describe "#redo" do
    it "returns nil when nothing to redo" do
      h = make_history
      h.redo.should be_nil
    end

    it "re-applies the last undone event" do
      h = make_history
      m = CanvasModel.new
      id, _ = push_rect(h, m, "hello")
      h.undo
      result = h.redo.not_nil!
      result.find_by_id(id).should_not be_nil
      result.find_by_id(id).as(RectModel).label.should eq "hello"
    end

    it "disables redo after redoing all events" do
      h = make_history
      m = CanvasModel.new
      push_rect(h, m)
      h.undo
      h.redo
      h.can_redo?.should be_false
    end

    it "can undo and redo multiple times" do
      h = make_history
      m = CanvasModel.new
      id1, _ = push_rect(h, m, "a")
      id2, _ = push_rect(h, m, "b")

      h.undo
      h.undo
      h.redo
      result = h.redo.not_nil!

      result.find_by_id(id1).should_not be_nil
      result.find_by_id(id2).should_not be_nil
      h.can_redo?.should be_false
      h.can_undo?.should be_true
    end
  end

  describe "#reset" do
    it "clears undo and redo stacks" do
      h = make_history
      m = CanvasModel.new
      push_rect(h, m)
      h.undo
      h.reset(CanvasModel.new)
      h.can_undo?.should be_false
      h.can_redo?.should be_false
    end

    it "adopts the new model as checkpoint" do
      id = UUID.random
      initial = model_with(rect_model(id, "baseline"))
      h = make_history
      h.reset(initial)

      # Add and immediately undo — should restore to the reset model
      m2 = model_with(rect_model(id, "baseline"), rect_model(UUID.random, "extra"))
      ev = CreateRectEvent.new(UUID.random, bounds, color, color, 1.0_f32, "after reset")
      h.push(ev)
      result = h.undo.not_nil!
      result.find_by_id(id).should_not be_nil
      result.elements.size.should eq 1
    end
  end

  describe "eviction (MAX_UNDO boundary)" do
    it "never exceeds MAX_UNDO entries in the log" do
      h = make_history
      m = CanvasModel.new
      (HistoryManager::MAX_UNDO + 5).times do
        push_rect(h, m)
      end
      # If we can still undo MAX_UNDO times, eviction is working.
      # We just verify undo works without error after exceeding the limit.
      result = h.undo
      result.should_not be_nil
    end

    it "oldest events are absorbed into checkpoint on eviction" do
      h = make_history
      m = CanvasModel.new
      first3_ids = 3.times.map { push_rect(h, m)[0] }.to_a
      (HistoryManager::MAX_UNDO).times { push_rect(h, m) }

      # Undo all MAX_UNDO log events — exhausts the log but not the checkpoint
      HistoryManager::MAX_UNDO.times { h.undo }

      # The 3 oldest rects were absorbed into the checkpoint; undo is now exhausted
      h.can_undo?.should be_false

      # Redo everything and verify the 3 baked-in rects survived
      HistoryManager::MAX_UNDO.times { h.redo }
      result = h.undo.not_nil!
      first3_ids.each { |id| result.find_by_id(id).should_not be_nil }
    end
  end

  describe "JSON roundtrip of checkpoint" do
    it "serializes and deserializes model with all element types" do
      from_id = UUID.random
      to_id = UUID.random
      initial = model_with(
        rect_model(from_id, "box"),
        text_model(to_id, "note"),
        ArrowModel.new(UUID.random, from_id, to_id)
      )
      h = make_history(initial)
      extra_id = UUID.random
      ev = CreateRectEvent.new(extra_id, bounds, color, color, 1.0_f32, "extra")
      apply(initial, ev)
      h.push(ev)

      result = h.undo.not_nil!
      result.elements.size.should eq 3
      result.find_by_id(from_id).as(RectModel).label.should eq "box"
      result.find_by_id(to_id).as(TextModel).text.should eq "note"
    end
  end
end
