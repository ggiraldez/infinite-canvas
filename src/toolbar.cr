require "raylib-cr"
require "./app_font"
require "./canvas"

class Toolbar
  TOOLS = [
    {Canvas::CursorTool::Selection, "Select", "S"},
    {Canvas::CursorTool::Rect, "Rect", "R"},
    {Canvas::CursorTool::Text, "Text", "T"},
    {Canvas::CursorTool::Arrow, "Arrow", "A"},
  ]

  BTN_W       = 80
  BTN_H       = 58
  GAP         =  6
  PANEL_P     =  8
  SECTION_GAP = 20 # wider gap between tool group and action group, holds the divider
  MARGIN_B    = 16
  FONT_KEY    = 20
  FONT_LBL    = 20

  BG            = R::Color.new(r: 255, g: 255, b: 255, a: 230)
  BORDER        = R::Color.new(r: 200, g: 200, b: 205, a: 255)
  DIVIDER       = R::Color.new(r: 210, g: 210, b: 215, a: 255)
  BTN_FILL      = R::Color.new(r: 240, g: 242, b: 245, a: 255)
  BTN_DISABLED  = R::Color.new(r: 248, g: 248, b: 250, a: 255)
  ACTIVE        = R::Color.new(r: 0, g: 120, b: 255, a: 255)
  TEXT_DARK     = R::Color.new(r: 50, g: 50, b: 60, a: 255)
  TEXT_DIM      = R::Color.new(r: 120, g: 120, b: 130, a: 255)
  TEXT_DISABLED = R::Color.new(r: 190, g: 190, b: 200, a: 255)
  KEY_ACT       = R::Color.new(r: 160, g: 215, b: 255, a: 255)

  # Checks for a mouse click on any toolbar button. Tool buttons switch the
  # active tool; action buttons (undo/redo) fire immediately. Blocks the canvas
  # from processing the same press. Returns true if the click was consumed.
  def update(canvas : Canvas) : Bool
    return false unless R.mouse_button_pressed?(R::MouseButton::Left)
    mouse = R.get_mouse_position
    panel_x, panel_y = panel_origin

    TOOLS.each_with_index do |(tool, _, _), i|
      if R.check_collision_point_rec?(mouse, tool_btn_rect(panel_x, panel_y, i))
        canvas.switch_tool(tool)
        canvas.block_mouse_press
        return true
      end
    end

    undo_rect, redo_rect = action_btn_rects(panel_x, panel_y)
    if R.check_collision_point_rec?(mouse, undo_rect) && canvas.can_undo?
      canvas.undo
      canvas.block_mouse_press
      return true
    end
    if R.check_collision_point_rec?(mouse, redo_rect) && canvas.can_redo?
      canvas.redo
      canvas.block_mouse_press
      return true
    end

    # Consume the press if the click landed anywhere on the panel.
    panel_rect = R::Rectangle.new(
      x: panel_x.to_f32, y: panel_y.to_f32,
      width: panel_total_w.to_f32, height: (BTN_H + 2 * PANEL_P).to_f32
    )
    if R.check_collision_point_rec?(mouse, panel_rect)
      canvas.block_mouse_press
      return true
    end

    false
  end

  def draw(canvas : Canvas)
    panel_x, panel_y = panel_origin
    total_w = panel_total_w
    total_h = BTN_H + 2 * PANEL_P

    panel = R::Rectangle.new(x: panel_x.to_f32, y: panel_y.to_f32, width: total_w.to_f32, height: total_h.to_f32)
    R.draw_rectangle_rec(panel, BG)
    R.draw_rectangle_lines_ex(panel, 1.0_f32, BORDER)

    # Divider between tool group and action group
    divider_x = panel_x + PANEL_P + TOOLS.size * BTN_W + (TOOLS.size - 1) * GAP + SECTION_GAP // 2
    R.draw_line(divider_x, panel_y + PANEL_P, divider_x, panel_y + total_h - PANEL_P, DIVIDER)

    draw_tool_buttons(canvas, panel_x, panel_y)
    draw_action_buttons(canvas, panel_x, panel_y)
  end

  private def draw_tool_buttons(canvas : Canvas, panel_x : Int32, panel_y : Int32)
    active = canvas.cursor_tool
    TOOLS.each_with_index do |(tool, label, key), i|
      btn = tool_btn_rect(panel_x, panel_y, i)
      bx = btn.x.to_i
      by = btn.y.to_i

      if tool == active
        R.draw_rectangle_rec(btn, ACTIVE)
        text_color = R::WHITE
        key_color = KEY_ACT
      else
        R.draw_rectangle_rec(btn, BTN_FILL)
        text_color = TEXT_DARK
        key_color = TEXT_DIM
      end

      key_w = AppFont.measure(key, FONT_KEY)
      AppFont.draw(key, bx + (BTN_W - key_w) / 2, by + 9, FONT_KEY, key_color)

      lbl_w = AppFont.measure(label, FONT_LBL)
      AppFont.draw(label, bx + (BTN_W - lbl_w) / 2, by + BTN_H - FONT_LBL - 9, FONT_LBL, text_color)
    end
  end

  private def draw_action_buttons(canvas : Canvas, panel_x : Int32, panel_y : Int32)
    undo_rect, redo_rect = action_btn_rects(panel_x, panel_y)
    draw_action_btn(undo_rect, "Undo", "C-Z", canvas.can_undo?)
    draw_action_btn(redo_rect, "Redo", "C-Y", canvas.can_redo?)
  end

  private def draw_action_btn(btn : R::Rectangle, label : String, key : String, enabled : Bool)
    bx = btn.x.to_i
    by = btn.y.to_i

    if enabled
      R.draw_rectangle_rec(btn, BTN_FILL)
      text_color = TEXT_DARK
      key_color = TEXT_DIM
    else
      R.draw_rectangle_rec(btn, BTN_DISABLED)
      text_color = TEXT_DISABLED
      key_color = TEXT_DISABLED
    end

    key_w = AppFont.measure(key, FONT_KEY)
    AppFont.draw(key, bx + (BTN_W - key_w) / 2, by + 9, FONT_KEY, key_color)

    lbl_w = AppFont.measure(label, FONT_LBL)
    AppFont.draw(label, bx + (BTN_W - lbl_w) / 2, by + BTN_H - FONT_LBL - 9, FONT_LBL, text_color)
  end

  private def panel_origin : {Int32, Int32}
    px = (R.get_screen_width - panel_total_w) // 2
    py = R.get_screen_height - BTN_H - 2 * PANEL_P - MARGIN_B
    {px, py}
  end

  private def panel_total_w : Int32
    n = TOOLS.size
    n * BTN_W + (n - 1) * GAP + SECTION_GAP + 2 * BTN_W + GAP + 2 * PANEL_P
  end

  private def tool_btn_rect(panel_x : Int32, panel_y : Int32, i : Int32) : R::Rectangle
    bx = panel_x + PANEL_P + i * (BTN_W + GAP)
    by = panel_y + PANEL_P
    R::Rectangle.new(x: bx.to_f32, y: by.to_f32, width: BTN_W.to_f32, height: BTN_H.to_f32)
  end

  private def action_btn_rects(panel_x : Int32, panel_y : Int32) : {R::Rectangle, R::Rectangle}
    n = TOOLS.size
    actions_x = panel_x + PANEL_P + n * BTN_W + (n - 1) * GAP + SECTION_GAP
    by = panel_y + PANEL_P
    undo = R::Rectangle.new(x: actions_x.to_f32, y: by.to_f32, width: BTN_W.to_f32, height: BTN_H.to_f32)
    redo = R::Rectangle.new(x: (actions_x + BTN_W + GAP).to_f32, y: by.to_f32, width: BTN_W.to_f32, height: BTN_H.to_f32)
    {undo, redo}
  end
end
