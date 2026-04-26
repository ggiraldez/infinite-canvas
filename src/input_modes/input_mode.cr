abstract class InputMode
  abstract def on_mouse_press(canvas : Canvas, mouse_world : R::Vector2,
                              mouse_screen : R::Vector2, is_double_click : Bool) : InputMode
  abstract def on_mouse_drag(canvas : Canvas, mouse_world : R::Vector2) : InputMode
  abstract def on_mouse_release(canvas : Canvas, mouse_world : R::Vector2) : InputMode
  abstract def on_escape(canvas : Canvas) : InputMode

  def deactivate(canvas : Canvas) : Nil; end
  def draft_rect : {R::Vector2, R::Vector2}?; nil; end
  def draft_arrow_line : {R::Vector2, R::Vector2}?; nil; end
  def rubber_band_select? : Bool; false; end
  def accepts_text_input? : Bool; false; end
  def text_selecting? : Bool; false; end
  def cursor_tool : Canvas::CursorTool?; nil; end
end
