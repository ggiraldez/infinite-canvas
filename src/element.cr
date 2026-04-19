require "raylib-cr"
require "uuid"

alias R = Raylib

# Abstract base for element serialisation data — concrete types defined in persistence.cr.
abstract class ElementData
  abstract def to_element : Element
end

# Base class for anything that lives on the canvas.
# Positions and sizes are in world space (not screen space).
abstract class Element
  property bounds : R::Rectangle
  getter id : UUID

  def initialize(@bounds : R::Rectangle, @id : UUID = UUID.random)
  end

  def contains?(world_point : R::Vector2) : Bool
    R.check_collision_point_rec?(world_point, bounds)
  end

  # Minimum dimensions required to display this element's content without clipping.
  # Subclasses override to account for text or other content.
  def min_size : {Float32, Float32}
    {4.0_f32, 4.0_f32}
  end

  # Called once per printable character pressed while this element is selected.
  def handle_char_input(ch : Char); end

  # Called when Enter is pressed while this element is selected.
  def handle_enter; end

  # Called when Backspace is pressed while this element is selected.
  def handle_backspace; end

  # Called when Ctrl+Backspace is pressed — deletes the word left of the cursor.
  def handle_backspace_word; end

  # Cursor movement — no-op in the base class; TextElement overrides these.
  def handle_cursor_left(shift : Bool = false); end
  def handle_cursor_right(shift : Bool = false); end
  def handle_cursor_word_left(shift : Bool = false); end
  def handle_cursor_word_right(shift : Bool = false); end
  def handle_cursor_up(shift : Bool = false); end
  def handle_cursor_down(shift : Bool = false); end
  # Clears any active text selection — no-op unless the element uses TextEditing.
  def clear_selection; end

  # Returns the selected text as a String, or nil if there is no selection.
  def handle_copy : String?; nil; end

  # Cuts the selected text: returns it and deletes it, or nil if there is no selection.
  def handle_cut : String?; nil; end

  # Inserts text at the cursor, replacing any active selection.
  def handle_paste(text : String); end

  # Whether the element can be manually resized by dragging handles.
  # Text nodes return false — their size is always derived from their content.
  def resizable? : Bool
    true
  end

  # Whether resize handles are limited to the left and right edges only.
  # TextElement uses this so only width can be dragged; height stays dynamic.
  def resizable_width_only? : Bool
    false
  end

  # Expands bounds if content no longer fits after a text change.
  def fit_content; end

end

require "./text_editing"
require "./rect_element"
require "./text_element"
require "./arrow_element"
