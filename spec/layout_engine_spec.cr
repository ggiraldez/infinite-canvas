require "spec"
require "../src/model"
require "../src/text_layout"
require "../src/render_data"
require "../src/layout_engine"

# Consistent stub measurer: per-string width includes inter-character spacing,
# matching how Raylib behaves, so results are coherent with TextLayout.compute.
# 10 px per char + (n-1) * (font_size / 10) px spacing for n-char strings.
private def stub_measure : Measurer
  Proc(String, Int32, Int32).new do |s, font_size|
    spacing = font_size / 10
    (s.size * 10 + [s.size - 1, 0].max * spacing).to_i32
  end
end

private def make_engine
  LayoutEngine.new(stub_measure)
end

describe LayoutEngine do
  describe "#layout" do
    it "produces an entry for every element in the model" do
      rid = UUID.random
      tid = UUID.random
      aid = UUID.random
      model = CanvasModel.new
      model.elements << RectModel.new(rid, BoundsData.new(0_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8),
        2_f32, "")
      model.elements << TextModel.new(tid, BoundsData.new(0_f32, 0_f32, 200_f32, 40_f32), "hi")
      model.elements << ArrowModel.new(aid, rid, tid)

      rd = make_engine.layout(model)

      rd.has_key?(rid).should be_true
      rd.has_key?(tid).should be_true
      rd.has_key?(aid).should be_true
    end

    # ── TextRenderData ─────────────────────────────────────────────────────────

    it "returns TextRenderData for a text element" do
      id    = UUID.random
      model = CanvasModel.new
      model.elements << TextModel.new(id, BoundsData.new(0_f32, 0_f32, 200_f32, 40_f32), "hello")

      rd = make_engine.layout(model)

      rd[id].should be_a(TextRenderData)
    end

    it "positions a text element at its model coordinates" do
      id    = UUID.random
      model = CanvasModel.new
      model.elements << TextModel.new(id, BoundsData.new(10_f32, 20_f32, 200_f32, 40_f32), "hi")

      t = make_engine.layout(model)[id].as(TextRenderData)

      t.bounds.x.should eq 10_f32
      t.bounds.y.should eq 20_f32
    end

    it "sizes an empty text element around the cursor placeholder" do
      id    = UUID.random
      model = CanvasModel.new
      model.elements << TextModel.new(id, BoundsData.new(0_f32, 0_f32, 100_f32, 40_f32), "")

      t = make_engine.layout(model)[id].as(TextRenderData)

      # cursor_w = 1 char * 10 = 10; content_w = 10 + 16 = 26; content_h = 20 + 16 = 36
      t.bounds.w.should eq 26_f32
      t.bounds.h.should eq 36_f32
      t.line_runs.should eq [{"", 0}]
      t.wraps.should be_false
    end

    it "produces a single line_run when text fits on one line" do
      id    = UUID.random
      model = CanvasModel.new
      # "hi" = 2*10 + 1*2 = 22 px wide with consistent stub (font_size=20, spacing=2)
      # content_w = 22+16 = 38; avail_w = 22 → full_w = 22 ≤ 22 → no wrap
      model.elements << TextModel.new(id, BoundsData.new(0_f32, 0_f32, 200_f32, 40_f32), "hi")

      t = make_engine.layout(model)[id].as(TextRenderData)

      t.line_runs.should eq [{"hi", 0}]
      t.wraps.should be_false
    end

    it "sets wraps=true and adjusts height for fixed_width text" do
      id    = UUID.random
      model = CanvasModel.new
      # width=60, avail_w=44; "hello world"=11 chars → wraps
      model.elements << TextModel.new(id, BoundsData.new(0_f32, 0_f32, 60_f32, 40_f32),
        "hello world", fixed_width: true)

      t = make_engine.layout(model)[id].as(TextRenderData)

      t.wraps.should be_true
      t.bounds.w.should eq 60_f32
      t.line_runs.size.should be > 1
      t.bounds.h.should eq (t.line_runs.size * LayoutEngine::TEXT_FONT_SIZE + LayoutEngine::TEXT_PADDING * 2).to_f32
    end

    it "applies max_auto_width cap and sets wraps=true" do
      id    = UUID.random
      model = CanvasModel.new
      # "hello world": content_w with consistent stub = (11*10 + 10*2) + 16 = 136;
      # cap = 80 < 136 → triggers auto-cap
      model.elements << TextModel.new(id, BoundsData.new(0_f32, 0_f32, 200_f32, 40_f32),
        "hello world", max_auto_width: 80_f32)

      t = make_engine.layout(model)[id].as(TextRenderData)

      t.wraps.should be_true
      t.bounds.w.should eq 80_f32
    end

    # ── RectRenderData ─────────────────────────────────────────────────────────

    it "returns RectRenderData for a rect element" do
      id    = UUID.random
      model = CanvasModel.new
      model.elements << RectModel.new(id, BoundsData.new(0_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8),
        2_f32, "OK")

      rd = make_engine.layout(model)

      rd[id].should be_a(RectRenderData)
    end

    it "preserves rect bounds unchanged" do
      id    = UUID.random
      model = CanvasModel.new
      model.elements << RectModel.new(id, BoundsData.new(5_f32, 15_f32, 120_f32, 60_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8),
        2_f32, "")

      r = make_engine.layout(model)[id].as(RectRenderData)

      r.bounds.x.should eq 5_f32
      r.bounds.y.should eq 15_f32
      r.bounds.w.should eq 120_f32
      r.bounds.h.should eq 60_f32
    end

    it "builds label_lines with measured widths for each line" do
      id    = UUID.random
      model = CanvasModel.new
      model.elements << RectModel.new(id, BoundsData.new(0_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8),
        2_f32, "ab\ncd")

      r = make_engine.layout(model)[id].as(RectRenderData)

      # stub: "ab" = 2*10 + 1*2 = 22; "cd" = 22
      r.label_lines.should eq [{"ab", 22}, {"cd", 22}]
    end

    it "returns a single empty label_line for an empty label" do
      id    = UUID.random
      model = CanvasModel.new
      model.elements << RectModel.new(id, BoundsData.new(0_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8),
        2_f32, "")

      r = make_engine.layout(model)[id].as(RectRenderData)

      r.label_lines.should eq [{"", 0}]
    end

    # ── ArrowRenderData ────────────────────────────────────────────────────────

    it "returns ArrowRenderData for an arrow element" do
      from_id  = UUID.random
      to_id    = UUID.random
      arrow_id = UUID.random
      model    = CanvasModel.new
      model.elements << RectModel.new(from_id, BoundsData.new(0_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8), 2_f32, "")
      model.elements << RectModel.new(to_id, BoundsData.new(200_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8), 2_f32, "")
      model.elements << ArrowModel.new(arrow_id, from_id, to_id)

      rd = make_engine.layout(model)

      rd[arrow_id].should be_a(ArrowRenderData)
    end

    it "produces centre-to-centre waypoints for a stub arrow" do
      from_id  = UUID.random
      to_id    = UUID.random
      arrow_id = UUID.random
      model    = CanvasModel.new
      model.elements << RectModel.new(from_id, BoundsData.new(0_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8), 2_f32, "")
      model.elements << RectModel.new(to_id, BoundsData.new(200_f32, 100_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8), 2_f32, "")
      model.elements << ArrowModel.new(arrow_id, from_id, to_id)

      a = make_engine.layout(model)[arrow_id].as(ArrowRenderData)

      a.waypoints.size.should eq 2
      a.waypoints[0].should eq({50_f32, 25_f32})    # centre of from element
      a.waypoints[1].should eq({250_f32, 125_f32})  # centre of to element
    end

    it "returns empty waypoints when an arrow endpoint is missing" do
      arrow_id = UUID.random
      model    = CanvasModel.new
      model.elements << ArrowModel.new(arrow_id, UUID.random, UUID.random)

      a = make_engine.layout(model)[arrow_id].as(ArrowRenderData)

      a.waypoints.should be_empty
    end
  end
end
