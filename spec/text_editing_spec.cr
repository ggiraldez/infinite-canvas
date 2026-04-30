require "spec"

# Stub Raylib module
module Raylib
  def self.get_time : Float64
    0.0_f64
  end
end

alias R = Raylib

# Stub Font class
# measure: 8 px per character, font-size-independent, no spacing.
# This makes nearest_col_for_x deterministic: column i snaps at x = (2i+1)*4.
class Font
  def measure(text : String, font_size : Number) : Int32
    text.size * 8
  end
end

require "../src/text_editing"

# Minimal host class — TextEditing needs editing_text r/w, editing_font_size, and font.
# fit_content is a no-op: we test only cursor/text logic, not layout.
private class Ed
  include TextEditing

  property editing_text : String
  property editing_font_size : Int32 = 10

  def font : Font
    @font ||= Font.new
  end

  def fit_content; end

  def initialize(text = "")
    @editing_text = text
    init_cursor
  end

  # Expose internals needed for assertions.
  def cursor
    @cursor_pos
  end

  def anchor
    @selection_anchor
  end

  def preferred_x
    @preferred_x
  end

  # Place cursor at an arbitrary position for setup.
  def cursor=(pos : Int32)
    @cursor_pos = pos
  end

  def anchor=(pos : Int32?)
    @selection_anchor = pos
  end
end

# ── Helpers ───────────────────────────────────────────────────────────────────

# With the 8px-per-char stub, nearest_col_for_x snaps at midpoints (2i+1)*4.
# measure_text("hello") = 40 → nearest_col_for_x(any_line, 40) returns
# the first column whose midpoint exceeds 40, or the line length.
# Concretely: a target of N*8 lands exactly at midpoint of col N, so it snaps
# to col N (since the condition is strict <). Use N*8+1 to force col N+1, or
# target far beyond line length to land at the end.
BIG = 9999

describe "TextEditing" do
  # ── init_cursor ─────────────────────────────────────────────────────────────

  describe "init_cursor" do
    it "places cursor at end of initial text" do
      Ed.new("hello").cursor.should eq 5
    end

    it "places cursor at 0 for empty text" do
      Ed.new("").cursor.should eq 0
    end
  end

  # ── handle_char_input ───────────────────────────────────────────────────────

  describe "#handle_char_input" do
    it "appends a char when cursor is at end" do
      e = Ed.new("hi")
      e.handle_char_input('!')
      e.editing_text.should eq "hi!"
      e.cursor.should eq 3
    end

    it "inserts a char at mid-string position" do
      e = Ed.new("hllo")
      e.cursor = 1
      e.handle_char_input('e')
      e.editing_text.should eq "hello"
      e.cursor.should eq 2
    end

    it "inserts into an empty string" do
      e = Ed.new
      e.handle_char_input('a')
      e.editing_text.should eq "a"
      e.cursor.should eq 1
    end

    it "replaces the active selection" do
      e = Ed.new("hello")
      e.cursor = 2
      e.anchor = 5
      e.handle_char_input('!')
      e.editing_text.should eq "he!"
      e.cursor.should eq 3
      e.anchor.should be_nil
    end

    it "clears preferred_x" do
      e = Ed.new("a\nb")
      e.handle_cursor_up
      e.preferred_x.should_not be_nil
      e.handle_char_input('x')
      e.preferred_x.should be_nil
    end
  end

  # ── handle_enter ────────────────────────────────────────────────────────────

  describe "#handle_enter" do
    it "inserts a newline at the cursor" do
      e = Ed.new("ab")
      e.cursor = 1
      e.handle_enter
      e.editing_text.should eq "a\nb"
      e.cursor.should eq 2
    end
  end

  # ── handle_backspace ────────────────────────────────────────────────────────

  describe "#handle_backspace" do
    it "deletes the char before the cursor" do
      e = Ed.new("hello")
      e.handle_backspace
      e.editing_text.should eq "hell"
      e.cursor.should eq 4
    end

    it "is a no-op when cursor is at position 0" do
      e = Ed.new("hi")
      e.cursor = 0
      e.handle_backspace
      e.editing_text.should eq "hi"
      e.cursor.should eq 0
    end

    it "deletes the selection instead of one char" do
      e = Ed.new("hello")
      e.cursor = 2
      e.anchor = 4
      e.handle_backspace
      e.editing_text.should eq "heo"
      e.cursor.should eq 2
      e.anchor.should be_nil
    end
  end

  # ── handle_backspace_word ───────────────────────────────────────────────────

  describe "#handle_backspace_word" do
    it "deletes the word left of the cursor" do
      e = Ed.new("hello world")
      e.handle_backspace_word
      e.editing_text.should eq "hello "
      e.cursor.should eq 6
    end

    it "deletes leading whitespace then the word before it" do
      e = Ed.new("hello   ")
      e.handle_backspace_word
      e.editing_text.should eq ""
      e.cursor.should eq 0
    end

    it "is a no-op when cursor is at position 0" do
      e = Ed.new("hi")
      e.cursor = 0
      e.handle_backspace_word
      e.editing_text.should eq "hi"
    end

    it "deletes the selection instead of a word" do
      e = Ed.new("hello world")
      e.cursor = 5
      e.anchor = 11
      e.handle_backspace_word
      e.editing_text.should eq "hello"
      e.cursor.should eq 5
    end

    it "deletes the whitespace separator and the preceding word when cursor is right after a space" do
      e = Ed.new("hello world")
      e.cursor = 6 # just past the space: skips ' ' then 'hello'
      e.handle_backspace_word
      e.editing_text.should eq "world"
      e.cursor.should eq 0
    end
  end

  # ── handle_cursor_left / right ──────────────────────────────────────────────

  describe "#handle_cursor_left" do
    it "moves cursor one step left" do
      e = Ed.new("hello")
      e.handle_cursor_left
      e.cursor.should eq 4
    end

    it "clamps at position 0" do
      e = Ed.new("hi")
      e.cursor = 0
      e.handle_cursor_left
      e.cursor.should eq 0
    end

    it "clears preferred_x" do
      e = Ed.new("a\nb")
      e.handle_cursor_up
      e.preferred_x.should_not be_nil
      e.handle_cursor_left
      e.preferred_x.should be_nil
    end
  end

  describe "#handle_cursor_right" do
    it "moves cursor one step right" do
      e = Ed.new("hello")
      e.cursor = 0
      e.handle_cursor_right
      e.cursor.should eq 1
    end

    it "clamps at end of text" do
      e = Ed.new("hi")
      e.handle_cursor_right
      e.cursor.should eq 2
    end
  end

  # ── handle_cursor_word_left / right ─────────────────────────────────────────

  describe "#handle_cursor_word_left" do
    it "skips back over a word" do
      e = Ed.new("hello world")
      e.handle_cursor_word_left
      e.cursor.should eq 6
    end

    it "skips whitespace then the word before it" do
      e = Ed.new("hello   ")
      e.handle_cursor_word_left
      e.cursor.should eq 0
    end

    it "is a no-op at position 0" do
      e = Ed.new("hi")
      e.cursor = 0
      e.handle_cursor_word_left
      e.cursor.should eq 0
    end

    it "clears anchor when shift is not held" do
      e = Ed.new("hello world")
      e.anchor = 5
      e.handle_cursor_word_left(shift: false)
      e.anchor.should be_nil
    end
  end

  describe "#handle_cursor_word_right" do
    it "skips forward over a word" do
      e = Ed.new("hello world")
      e.cursor = 0
      e.handle_cursor_word_right
      e.cursor.should eq 5
    end

    it "skips whitespace then stops at end of next word" do
      e = Ed.new("hello world")
      e.cursor = 5
      e.handle_cursor_word_right
      e.cursor.should eq 11
    end

    it "is a no-op at end of text" do
      e = Ed.new("hi")
      e.handle_cursor_word_right
      e.cursor.should eq 2
    end
  end

  # ── selection_range / anchor_for_shift / clear_selection ────────────────────

  describe "#selection_range" do
    it "returns nil when there is no anchor" do
      Ed.new("hi").selection_range.should be_nil
    end

    it "returns nil when anchor equals cursor (zero-width selection)" do
      e = Ed.new("hi")
      e.cursor = 1
      e.anchor = 1
      e.selection_range.should be_nil
    end

    it "returns {min, max} when cursor is right of anchor" do
      e = Ed.new("hello")
      e.cursor = 4
      e.anchor = 1
      e.selection_range.should eq({1, 4})
    end

    it "returns {min, max} when cursor is left of anchor" do
      e = Ed.new("hello")
      e.cursor = 1
      e.anchor = 4
      e.selection_range.should eq({1, 4})
    end
  end

  describe "shift + movement (anchor_for_shift)" do
    it "sets anchor on first shifted left-arrow" do
      e = Ed.new("hello")
      e.handle_cursor_left(shift: true)
      e.anchor.should eq 5
      e.cursor.should eq 4
    end

    it "extends selection on subsequent shifted moves" do
      e = Ed.new("hello")
      e.handle_cursor_left(shift: true)
      e.handle_cursor_left(shift: true)
      e.anchor.should eq 5
      e.cursor.should eq 3
      e.selection_range.should eq({3, 5})
    end

    it "clears anchor when shift is released" do
      e = Ed.new("hello")
      e.handle_cursor_left(shift: true)
      e.handle_cursor_left(shift: false)
      e.anchor.should be_nil
    end
  end

  describe "#clear_selection" do
    it "removes the selection anchor" do
      e = Ed.new("hello")
      e.anchor = 2
      e.clear_selection
      e.anchor.should be_nil
    end
  end

  # ── handle_copy / handle_cut ─────────────────────────────────────────────────

  describe "#handle_copy" do
    it "returns nil when there is no selection" do
      Ed.new("hello").handle_copy.should be_nil
    end

    it "returns the selected text without modifying the element" do
      e = Ed.new("hello world")
      e.cursor = 6
      e.anchor = 11
      e.handle_copy.should eq "world"
      e.editing_text.should eq "hello world"
      e.cursor.should eq 6
    end

    it "returns text in document order regardless of anchor direction" do
      e = Ed.new("hello")
      e.cursor = 1
      e.anchor = 4
      e.handle_copy.should eq "ell"
    end
  end

  describe "#handle_cut" do
    it "returns nil when there is no selection" do
      Ed.new("hello").handle_cut.should be_nil
    end

    it "returns the selected text and removes it from the element" do
      e = Ed.new("hello world")
      e.cursor = 6
      e.anchor = 11
      e.handle_cut.should eq "world"
      e.editing_text.should eq "hello "
      e.cursor.should eq 6
      e.anchor.should be_nil
    end

    it "cuts correctly when anchor precedes cursor" do
      e = Ed.new("abcde")
      e.cursor = 4
      e.anchor = 1
      e.handle_cut.should eq "bcd"
      e.editing_text.should eq "ae"
      e.cursor.should eq 1
    end
  end

  # ── handle_paste ─────────────────────────────────────────────────────────────

  describe "#handle_paste" do
    it "inserts text at cursor position" do
      e = Ed.new("hworld")
      e.cursor = 1
      e.handle_paste("ello ")
      e.editing_text.should eq "hello world"
      e.cursor.should eq 6
    end

    it "appends when cursor is at end" do
      e = Ed.new("hello")
      e.handle_paste(" world")
      e.editing_text.should eq "hello world"
      e.cursor.should eq 11
    end

    it "replaces the active selection" do
      e = Ed.new("hello world")
      e.cursor = 6
      e.anchor = 11
      e.handle_paste("earth")
      e.editing_text.should eq "hello earth"
      e.cursor.should eq 11
      e.anchor.should be_nil
    end

    it "is a no-op for an empty string" do
      e = Ed.new("hello")
      e.handle_paste("")
      e.editing_text.should eq "hello"
      e.cursor.should eq 5
    end
  end

  # ── selection_line_ranges ────────────────────────────────────────────────────

  describe "#selection_line_ranges" do
    it "returns a single range when selection is within one line" do
      e = Ed.new("hello world")
      e.selection_line_ranges(2, 7).should eq [{0, 2, 7}]
    end

    it "spans two lines when selection crosses a newline" do
      e = Ed.new("hello\nworld")
      result = e.selection_line_ranges(3, 8)
      result.should eq [{0, 3, 5}, {1, 0, 2}]
    end

    it "covers whole lines for a full-spanning selection" do
      e = Ed.new("hi\nbye")
      result = e.selection_line_ranges(0, 6)
      result.should eq [{0, 0, 2}, {1, 0, 3}]
    end

    it "returns a zero-width entry when sel_start == sel_end (no guard in the method)" do
      # The method does not filter zero-width ranges; the renderer ignores them.
      e = Ed.new("hello")
      e.selection_line_ranges(2, 2).should eq [{0, 2, 2}]
    end
  end

  # ── handle_cursor_up / down ──────────────────────────────────────────────────
  # With the 8px/char stub, measure_text of an N-char line = N*8.
  # nearest_col_for_x with target >= line_length*8 lands at the end of the line.

  describe "#handle_cursor_up" do
    it "is a no-op when already on the first line" do
      e = Ed.new("hello")
      e.cursor = 2
      e.handle_cursor_up
      e.cursor.should eq 2
    end

    it "moves to the previous line at the matching column" do
      # "hello\nworld" — cursor at end of "world" (11).
      # target_x = measure_text("world") = 40 → col 5 on "hello" (end).
      e = Ed.new("hello\nworld")
      e.handle_cursor_up
      e.cursor.should eq 5
    end

    it "moves to start of previous line when target_x is 0" do
      # Cursor at start of second line (pos 6 in "hello\nworld").
      # target_x = measure_text("") = 0 → col 0 on "hello".
      e = Ed.new("hello\nworld")
      e.cursor = 6
      e.handle_cursor_up
      e.cursor.should eq 0
    end

    it "retains preferred_x across multiple up-presses (sticky column)" do
      # "hello\nhi\nworld" — cursor at end (14).
      # First up: target=40 (measure "world"), snaps to end of "hi" (pos 8).
      # Second up: sticky target still 40, snaps to end of "hello" (pos 5).
      e = Ed.new("hello\nhi\nworld")
      e.handle_cursor_up
      e.cursor.should eq 8 # end of "hi"
      e.handle_cursor_up
      e.cursor.should eq 5 # end of "hello"
    end

    it "sets a selection anchor when shift is held" do
      e = Ed.new("hello\nworld")
      e.handle_cursor_up(shift: true)
      e.anchor.should eq 11
      e.selection_range.should_not be_nil
    end
  end

  describe "#handle_cursor_down" do
    it "is a no-op when already on the last line" do
      e = Ed.new("hello")
      e.cursor = 2
      e.handle_cursor_down
      e.cursor.should eq 2
    end

    it "moves to the next line at the matching column" do
      # Cursor at end of "hello" (5). target_x = 40 → end of "world" = pos 11.
      e = Ed.new("hello\nworld")
      e.cursor = 5
      e.handle_cursor_down
      e.cursor.should eq 11
    end

    it "moves to start of next line when target_x is 0" do
      # Cursor at start of "hello" (0). measure_text("") = 0 → col 0 on "world".
      e = Ed.new("hello\nworld")
      e.cursor = 0
      e.handle_cursor_down
      e.cursor.should eq 6
    end

    it "sets a selection anchor when shift is held" do
      e = Ed.new("hello\nworld")
      e.cursor = 0
      e.handle_cursor_down(shift: true)
      e.anchor.should eq 0
      e.selection_range.should_not be_nil
    end
  end

  # ── lines_before_cursor ──────────────────────────────────────────────────────

  describe "#lines_before_cursor" do
    it "returns the single line up to cursor on a one-line string" do
      e = Ed.new("hello world")
      e.cursor = 5
      e.lines_before_cursor.should eq ["hello"]
    end

    it "returns multiple lines when text has newlines before cursor" do
      e = Ed.new("a\nb\nc")
      e.lines_before_cursor.should eq ["a", "b", "c"]
    end

    it "returns [\"\"] at cursor position 0" do
      e = Ed.new("hello")
      e.cursor = 0
      e.lines_before_cursor.should eq [""]
    end
  end
end
