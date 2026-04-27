require "raylib-cr"
require "./canvas"

class Toolbar
  TOOLS = [
    {Canvas::CursorTool::Selection, "Select", "S"},
    {Canvas::CursorTool::Rect, "Rect", "R"},
    {Canvas::CursorTool::Text, "Text", "T"},
    {Canvas::CursorTool::Arrow, "Arrow", "A"},
  ]

  BTN_W    =  80
  BTN_H    =  58
  GAP      =   6
  PANEL_P  =   8
  MARGIN_B =  16
  FONT_KEY =  16
  FONT_LBL =  20

  BG        = R::Color.new(r: 255, g: 255, b: 255, a: 230)
  BORDER    = R::Color.new(r: 200, g: 200, b: 205, a: 255)
  BTN_FILL  = R::Color.new(r: 240, g: 242, b: 245, a: 255)
  ACTIVE    = R::Color.new(r: 0, g: 120, b: 255, a: 255)
  TEXT_DIM  = R::Color.new(r: 120, g: 120, b: 130, a: 255)
  TEXT_DARK = R::Color.new(r: 50, g: 50, b: 60, a: 255)
  KEY_ACT   = R::Color.new(r: 160, g: 215, b: 255, a: 255)

  # Checks for a mouse click on any toolbar button. If one is hit, switches
  # the active tool and blocks the canvas from processing the same press.
  # Returns true if the click was consumed.
  def update(canvas : Canvas) : Bool
    return false unless R.mouse_button_pressed?(R::MouseButton::Left)
    mouse = R.get_mouse_position
    panel_x, panel_y = panel_origin
    TOOLS.each_with_index do |(tool, _, _), i|
      btn = button_rect(panel_x, panel_y, i)
      if R.check_collision_point_rec?(mouse, btn)
        canvas.switch_tool(tool)
        canvas.block_mouse_press
        return true
      end
    end
    false
  end

  def draw(canvas : Canvas)
    panel_x, panel_y = panel_origin
    total_w = TOOLS.size * BTN_W + (TOOLS.size - 1) * GAP + 2 * PANEL_P
    total_h = BTN_H + 2 * PANEL_P
    panel = R::Rectangle.new(x: panel_x.to_f32, y: panel_y.to_f32, width: total_w.to_f32, height: total_h.to_f32)
    R.draw_rectangle_rec(panel, BG)
    R.draw_rectangle_lines_ex(panel, 1.0_f32, BORDER)

    active = canvas.cursor_tool
    TOOLS.each_with_index do |(tool, label, key), i|
      btn = button_rect(panel_x, panel_y, i)
      bx = btn.x.to_i
      by = btn.y.to_i

      if tool == active
        R.draw_rectangle_rec(btn, ACTIVE)
        text_color = R::WHITE
        key_color  = KEY_ACT
      else
        R.draw_rectangle_rec(btn, BTN_FILL)
        text_color = TEXT_DARK
        key_color  = TEXT_DIM
      end

      key_w = R.measure_text(key, FONT_KEY)
      R.draw_text(key, bx + (BTN_W - key_w) / 2, by + 9, FONT_KEY, key_color)

      lbl_w = R.measure_text(label, FONT_LBL)
      R.draw_text(label, bx + (BTN_W - lbl_w) / 2, by + BTN_H - FONT_LBL - 9, FONT_LBL, text_color)
    end
  end

  private def panel_origin : {Int32, Int32}
    n = TOOLS.size
    total_w = n * BTN_W + (n - 1) * GAP + 2 * PANEL_P
    total_h = BTN_H + 2 * PANEL_P
    px = (R.get_screen_width - total_w) // 2
    py = R.get_screen_height - total_h - MARGIN_B
    {px, py}
  end

  private def button_rect(panel_x : Int32, panel_y : Int32, i : Int32) : R::Rectangle
    bx = panel_x + PANEL_P + i * (BTN_W + GAP)
    by = panel_y + PANEL_P
    R::Rectangle.new(x: bx.to_f32, y: by.to_f32, width: BTN_W.to_f32, height: BTN_H.to_f32)
  end
end
