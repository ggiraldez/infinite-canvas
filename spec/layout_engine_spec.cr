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

    it "wraps multi-paragraph text and computes correct height" do
      id    = UUID.random
      model = CanvasModel.new
      # Two paragraphs separated by \n, each long enough to wrap at cap=80.
      # "hello world\ngoodbye world" — both lines > 80px wide with stub.
      # With cap=80, avail_w=64, each paragraph wraps independently.
      model.elements << TextModel.new(id, BoundsData.new(0_f32, 0_f32, 200_f32, 40_f32),
        "hello world\ngoodbye world", max_auto_width: 80_f32)

      t = make_engine.layout(model)[id].as(TextRenderData)

      t.wraps.should be_true
      t.line_runs.size.should be > 2
      t.bounds.h.should eq (t.line_runs.size * LayoutEngine::TEXT_FONT_SIZE + LayoutEngine::TEXT_PADDING * 2).to_f32
    end

    # ── layout_text_element (public single-element entry point) ─────────────────

    it "layout_text_element produces the same result as layout for that element" do
      id    = UUID.random
      model = CanvasModel.new
      model.elements << TextModel.new(id, BoundsData.new(5_f32, 10_f32, 200_f32, 40_f32), "hello")

      engine = make_engine
      via_layout = engine.layout(model)[id].as(TextRenderData)
      via_single = engine.layout_text_element(
        TextModel.new(id, BoundsData.new(5_f32, 10_f32, 200_f32, 40_f32), "hello"))

      via_single.bounds.x.should eq via_layout.bounds.x
      via_single.bounds.w.should eq via_layout.bounds.w
      via_single.line_runs.should eq via_layout.line_runs
      via_single.wraps.should eq via_layout.wraps
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

    it "produces orthogonal waypoints for a right-then-down path (L-shape)" do
      # from=(0,0,100,50) centre=(50,25); to=(200,100,100,50) centre=(250,125)
      # dx=200>0, dy=100>0 → Option A: exit Right, enter Top
      # single arrow → frac_src=frac_tgt=0.5 → exit_y=25, entry_x=250
      # Option A valid → [{100,25},{250,25},{250,100}]
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

      a.waypoints.should eq [{100_f32, 25_f32}, {250_f32, 25_f32}, {250_f32, 100_f32}]
    end

    it "produces straight waypoints for a straight-routed arrow" do
      # from=(0,0,100,50) centre=(50,25); to=(200,0,100,50) centre=(250,25)
      # straight_route: border exit right of from = (100,25), left of to = (200,25)
      from_id  = UUID.random
      to_id    = UUID.random
      arrow_id = UUID.random
      model    = CanvasModel.new
      model.elements << RectModel.new(from_id, BoundsData.new(0_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8), 2_f32, "")
      model.elements << RectModel.new(to_id, BoundsData.new(200_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8), 2_f32, "")
      model.elements << ArrowModel.new(arrow_id, from_id, to_id, "straight")

      a = make_engine.layout(model)[arrow_id].as(ArrowRenderData)

      a.waypoints.should eq [{100_f32, 25_f32}, {200_f32, 25_f32}]
    end

    it "returns empty waypoints when an arrow endpoint is missing" do
      arrow_id = UUID.random
      model    = CanvasModel.new
      model.elements << ArrowModel.new(arrow_id, UUID.random, UUID.random)

      a = make_engine.layout(model)[arrow_id].as(ArrowRenderData)

      a.waypoints.should be_empty
    end

    # ── Side-fraction spread ───────────────────────────────────────────────────

    it "spreads two arrows that exit the same side of a shared source" do
      # A at (0,0,100,50); B at (200,0,100,50) centre_y=25; C at (200,200,100,50) centre_y=225
      # Both arrows exit the Right side of A (purely horizontal or diagonal right).
      # Arrow→B has other-endpoint centre_y=25 < Arrow→C centre_y=225
      # → Arrow→B gets rank 0: frac=1/3; Arrow→C gets rank 1: frac=2/3
      # Right-side exit: exit_y = A.y + frac * A.h = frac * 50
      # Arrow→B exit_y < Arrow→C exit_y  (spread ordering is correct)
      a_id      = UUID.random
      b_id      = UUID.random
      c_id      = UUID.random
      arrow1_id = UUID.random
      arrow2_id = UUID.random
      model     = CanvasModel.new
      model.elements << RectModel.new(a_id, BoundsData.new(0_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8), 2_f32, "")
      model.elements << RectModel.new(b_id, BoundsData.new(200_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8), 2_f32, "")
      model.elements << RectModel.new(c_id, BoundsData.new(200_f32, 200_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8), 2_f32, "")
      model.elements << ArrowModel.new(arrow1_id, a_id, b_id)
      model.elements << ArrowModel.new(arrow2_id, a_id, c_id)

      rd = make_engine.layout(model)
      a1 = rd[arrow1_id].as(ArrowRenderData)
      a2 = rd[arrow2_id].as(ArrowRenderData)

      # Both arrows must have waypoints (routing succeeded).
      a1.waypoints.should_not be_empty
      a2.waypoints.should_not be_empty

      # Arrow1→B exits higher (smaller y) than Arrow2→C because B is above C.
      a1.waypoints[0][1].should be < a2.waypoints[0][1]
    end

    it "gives a single arrow on a side the centre fraction (0.5)" do
      from_id  = UUID.random
      to_id    = UUID.random
      arrow_id = UUID.random
      model    = CanvasModel.new
      # Pure horizontal: exits Right side at centre (y=25 = 50*0.5)
      model.elements << RectModel.new(from_id, BoundsData.new(0_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8), 2_f32, "")
      model.elements << RectModel.new(to_id, BoundsData.new(200_f32, 0_f32, 100_f32, 50_f32),
        ColorData.new(255_u8, 0_u8, 0_u8, 255_u8), ColorData.new(0_u8, 0_u8, 0_u8, 255_u8), 2_f32, "")
      model.elements << ArrowModel.new(arrow_id, from_id, to_id)

      a = make_engine.layout(model)[arrow_id].as(ArrowRenderData)

      # Horizontal arrow: 3-segment right-to-left path; first waypoint is exit of from.
      # frac=0.5 → exit_y = 0 + 0.5*50 = 25 → first waypoint y = 25.
      a.waypoints[0][1].should eq 25_f32
    end
  end
end
