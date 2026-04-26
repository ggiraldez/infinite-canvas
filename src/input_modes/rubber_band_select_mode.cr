class RubberBandSelectMode < InputMode
  def initialize(@draw_start : R::Vector2)
    @draw_current = @draw_start
  end

  def draft_rect : {R::Vector2, R::Vector2}?
    {@draw_start, @draw_current}
  end

  def rubber_band_select? : Bool
    true
  end

  def on_mouse_press(canvas : Canvas, mouse_world : R::Vector2,
                     mouse_screen : R::Vector2, is_double_click : Bool) : InputMode
    IdleMode.new(Canvas::CursorTool::Selection)
  end

  def on_mouse_drag(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    @draw_current = mouse_world
    self
  end

  def on_mouse_release(canvas : Canvas, mouse_world : R::Vector2) : InputMode
    sel_rect = canvas.rect_from_points(@draw_start, @draw_current)
    indices  = (0...canvas.elements.size).select do |i|
      el = canvas.elements[i]
      !el.is_a?(ArrowElement) && canvas.rects_overlap?(sel_rect, el.bounds)
    end.to_a
    if indices.size == 1
      canvas.select_element(indices.first)
    elsif indices.size > 1
      canvas.select_multi(indices)
    end
    IdleMode.new(Canvas::CursorTool::Selection)
  end

  def on_escape(canvas : Canvas) : InputMode
    IdleMode.new(Canvas::CursorTool::Selection)
  end
end
