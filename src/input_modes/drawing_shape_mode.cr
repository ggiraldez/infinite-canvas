class DrawingShapeMode < InputMode
  def initialize(@draw_start : R::Vector2, @variant : Canvas::CursorTool)
    @draw_current = @draw_start
  end

  def cursor_tool : Canvas::CursorTool?
    @variant
  end

  def draft_rect : {R::Vector2, R::Vector2}?
    {@draw_start, @draw_current}
  end

  def on_mouse_press(canvas : Canvas, mouse_world : R::Vector2,
                     mouse_screen : R::Vector2, is_double_click : Bool) : InputMode
    IdleMode.new(@variant)
  end

  def on_mouse_drag(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    @draw_current = mouse_world
    self
  end

  def on_mouse_release(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    start   = @draw_start
    current = @draw_current
    dragged = canvas.rect_from_points(start, current)
    is_drag = dragged.width >= 4.0_f32 || dragged.height >= 4.0_f32
    maw     = R.get_screen_width.to_f32 / (2.0_f32 * canvas.camera.zoom)

    case @variant
    when Canvas::CursorTool::Rect
      b = is_drag ? dragged
                  : R::Rectangle.new(x: start.x, y: start.y,
                                     width: Canvas::DEFAULT_RECT_W, height: Canvas::DEFAULT_RECT_H)
      rect_id = UUID.random
      fill    = ColorData.new(90_u8, 140_u8, 220_u8, 200_u8)
      stroke  = ColorData.new(30_u8, 60_u8, 120_u8, 255_u8)
      canvas.emit(CreateRectEvent.new(rect_id,
        BoundsData.new(b.x, b.y, b.width, b.height), fill, stroke, 2.0_f32))
      canvas.select_element(canvas.elements.index { |e| e.id == rect_id })
      canvas.text_session_id = rect_id
      TextEditingMode.new(rect_id, Canvas::CursorTool::Selection)

    when Canvas::CursorTool::Text
      raw = is_drag ? R::Rectangle.new(x: start.x, y: start.y,
                                       width: dragged.width, height: dragged.height)
                    : R::Rectangle.new(x: start.x, y: start.y,
                                       width: 0.0_f32, height: 0.0_f32)
      text_id = UUID.random
      raw_bd  = BoundsData.new(raw.x, raw.y, raw.width, raw.height)
      tmp_m   = TextModel.new(text_id, raw_bd, "", false, maw)
      tmp_rd  = canvas.layout_engine.layout_text_element(tmp_m)
      canvas.emit(CreateTextEvent.new(text_id,
        BoundsData.new(tmp_rd.bounds.x, tmp_rd.bounds.y, tmp_rd.bounds.w, tmp_rd.bounds.h),
        "", false, maw))
      canvas.select_element(canvas.elements.index { |e| e.id == text_id })
      canvas.text_session_id = text_id
      TextEditingMode.new(text_id, Canvas::CursorTool::Selection)

    else
      IdleMode.new(@variant)
    end
  end

  def on_escape(canvas : Canvas) : InputMode
    IdleMode.new(@variant)
  end
end
