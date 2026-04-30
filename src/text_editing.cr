# ─── TextEditing mixin ────────────────────────────────────────────────────────

# Shared cursor-aware text editing behaviour for any element with an editable
# string field.  Including classes must implement:
#   def editing_text : String
#   def editing_text=(v : String)
#   def editing_font_size : Int32
#   def font : FontMetrics
module TextEditing
  @cursor_pos : Int32 = 0
  # Timestamp of the last keystroke — keeps the cursor solid for 0.5 s after input.
  @last_input_time : Float64 = 0.0
  # Preferred pixel x for vertical navigation (sticky column).
  # Set on the first Up/Down press; cleared by any other cursor movement.
  @preferred_x : Int32? = nil
  # Fixed end of any active selection; nil = no selection.
  # @cursor_pos is the "active" (moving) end.
  @selection_anchor : Int32? = nil

  def cursor_pos : Int32
    @cursor_pos
  end

  # Call at the end of initialize to place the cursor after existing text.
  private def init_cursor
    @cursor_pos = editing_text.chars.size
  end

  def handle_char_input(ch : Char)
    delete_selection # replace selection if one exists
    chars = editing_text.chars
    chars.insert(@cursor_pos, ch)
    self.editing_text = chars.join
    @cursor_pos += 1
    @preferred_x = nil
    reset_blink
  end

  def handle_enter
    handle_char_input('\n')
  end

  def handle_backspace
    if delete_selection # delete selection if one exists
      @preferred_x = nil
      reset_blink
      return
    end
    return if @cursor_pos == 0
    chars = editing_text.chars
    chars.delete_at(@cursor_pos - 1)
    self.editing_text = chars.join
    @cursor_pos -= 1
    @preferred_x = nil
    reset_blink
  end

  def handle_forward_delete
    if delete_selection
      @preferred_x = nil
      reset_blink
      return
    end
    chars = editing_text.chars
    return if @cursor_pos >= chars.size
    chars.delete_at(@cursor_pos)
    self.editing_text = chars.join
    @preferred_x = nil
    reset_blink
  end

  def handle_backspace_word
    if delete_selection
      @preferred_x = nil
      reset_blink
      return
    end
    return if @cursor_pos == 0
    chars = editing_text.chars
    pos = @cursor_pos
    while pos > 0 && chars[pos - 1].whitespace?
      pos -= 1
    end
    while pos > 0 && !chars[pos - 1].whitespace?
      pos -= 1
    end
    self.editing_text = (chars[0...pos] + chars[@cursor_pos...chars.size]).join
    @cursor_pos = pos
    @preferred_x = nil
    reset_blink
  end

  def handle_forward_delete_word
    if delete_selection
      @preferred_x = nil
      reset_blink
      return
    end
    chars = editing_text.chars
    return if @cursor_pos >= chars.size
    pos = @cursor_pos
    size = chars.size
    while pos < size && chars[pos].whitespace?
      pos += 1
    end
    while pos < size && !chars[pos].whitespace?
      pos += 1
    end
    self.editing_text = (chars[0...@cursor_pos] + chars[pos...size]).join
    @preferred_x = nil
    reset_blink
  end

  def handle_cursor_left(shift : Bool = false)
    anchor_for_shift(shift)
    @cursor_pos = [@cursor_pos - 1, 0].max
    @preferred_x = nil
    reset_blink
  end

  def handle_cursor_right(shift : Bool = false)
    anchor_for_shift(shift)
    @cursor_pos = [@cursor_pos + 1, editing_text.chars.size].min
    @preferred_x = nil
    reset_blink
  end

  def handle_cursor_word_left(shift : Bool = false)
    anchor_for_shift(shift)
    chars = editing_text.chars
    pos = @cursor_pos
    while pos > 0 && chars[pos - 1].whitespace?
      pos -= 1
    end
    while pos > 0 && !chars[pos - 1].whitespace?
      pos -= 1
    end
    @cursor_pos = pos
    @preferred_x = nil
    reset_blink
  end

  def handle_cursor_word_right(shift : Bool = false)
    anchor_for_shift(shift)
    chars = editing_text.chars
    pos = @cursor_pos
    size = chars.size
    while pos < size && chars[pos].whitespace?
      pos += 1
    end
    while pos < size && !chars[pos].whitespace?
      pos += 1
    end
    @cursor_pos = pos
    @preferred_x = nil
    reset_blink
  end

  def handle_cursor_up(shift : Bool = false)
    anchor_for_shift(shift)
    return if @cursor_pos == 0
    lines_b = lines_before_cursor
    return if lines_b.size <= 1
    target_x = @preferred_x || font.measure(lines_b.last)
    @preferred_x = target_x
    new_col = nearest_col_for_x(lines_b[-2], target_x)
    prefix = lines_b[0...-2].sum(0) { |l| l.size + 1 }
    @cursor_pos = prefix + new_col
    reset_blink
  end

  def handle_cursor_down(shift : Bool = false)
    anchor_for_shift(shift)
    return if @cursor_pos == editing_text.chars.size
    lines_b = lines_before_cursor
    all_lines = editing_text.split('\n')
    line_idx = lines_b.size - 1
    return if line_idx >= all_lines.size - 1
    target_x = @preferred_x || font.measure(lines_b.last)
    @preferred_x = target_x
    new_col = nearest_col_for_x(all_lines[line_idx + 1], target_x)
    prefix = (0..line_idx).sum { |i| all_lines[i].size + 1 }
    @cursor_pos = prefix + new_col
    reset_blink
  end

  # Selects the word around the current cursor position.
  # If *extend* is true, keeps the existing selection anchor and extends the
  # cursor to whichever word boundary stretches the selection further.
  def select_word_at_cursor(extend_sel : Bool = false)
    chars = editing_text.chars
    pos = @cursor_pos.clamp(0, chars.size)

    word_start = pos
    while word_start > 0 && !chars[word_start - 1].whitespace?
      word_start -= 1
    end
    word_end = pos
    while word_end < chars.size && !chars[word_end].whitespace?
      word_end += 1
    end

    return if word_start == word_end # cursor is on whitespace

    if extend_sel
      anchor = @selection_anchor || @cursor_pos
      @selection_anchor = anchor
      @cursor_pos = anchor <= word_start ? word_end : word_start
    else
      @selection_anchor = word_start
      @cursor_pos = word_end
    end
    @preferred_x = nil
    reset_blink
  end

  # Returns {min_pos, max_pos} when there is a non-empty selection, nil otherwise.
  def selection_range : {Int32, Int32}?
    return nil unless (anchor = @selection_anchor) && anchor != @cursor_pos
    {[anchor, @cursor_pos].min, [anchor, @cursor_pos].max}
  end

  # Clears the active selection. Called when another element gains focus.
  def clear_selection
    @selection_anchor = nil
  end

  def handle_copy : String?
    return nil unless (range = selection_range)
    editing_text.chars[range[0]...range[1]].join
  end

  def handle_cut : String?
    return nil unless (range = selection_range)
    text = editing_text.chars[range[0]...range[1]].join
    delete_selection
    @preferred_x = nil
    reset_blink

    text
  end

  def handle_paste(text : String)
    return if text.empty?
    delete_selection
    chars = editing_text.chars
    self.editing_text = (chars[0...@cursor_pos] + text.chars + chars[@cursor_pos...chars.size]).join
    @cursor_pos += text.chars.size
    @preferred_x = nil
    reset_blink
  end

  # True when the cursor glyph should be drawn this frame.
  def cursor_visible? : Bool
    now = R.get_time
    (now - @last_input_time < 0.5) || ((now * 2.0).to_i % 2 == 0)
  end

  # For a selection [sel_start, sel_end), returns an array of
  # {line_index, col_start, col_end} for each line that overlaps the selection.
  # Non-private so Renderer can call it for cursor drawing.
  def selection_line_ranges(sel_start : Int32, sel_end : Int32) : Array({Int32, Int32, Int32})
    result = [] of {Int32, Int32, Int32}
    pos = 0
    editing_text.split('\n').each_with_index do |line, line_idx|
      len = line.chars.size
      if pos < sel_end && pos + len > sel_start
        result << {line_idx, [sel_start - pos, 0].max, [sel_end - pos, len].min}
      end
      pos += len + 1
      break if pos >= sel_end
    end
    result
  end

  def lines_before_cursor : Array(String)
    editing_text.chars[0...@cursor_pos].join.split('\n')
  end

  # Returns the character column on *line* whose left edge is closest to
  # *target_x* pixels, using the midpoint of each glyph as the snap boundary.
  private def nearest_col_for_x(line : String, target_x : Int32) : Int32
    prev_x = 0
    line.chars.each_with_index do |_, i|
      curr_x = font.measure(line.chars[0, i + 1].join)
      return i if target_x < (prev_x + curr_x) / 2
      prev_x = curr_x
    end
    line.chars.size
  end

  # Directly sets anchor and cursor, e.g. for drag-selection logic that
  # computes the exact span externally.
  def set_selection(anchor : Int32, cursor : Int32)
    @selection_anchor = anchor
    @cursor_pos = cursor
    @preferred_x = nil
    reset_blink
  end

  # Sets @selection_anchor when shift is held; clears it otherwise.
  private def anchor_for_shift(shift : Bool)
    if shift
      @selection_anchor ||= @cursor_pos
    else
      @selection_anchor = nil
    end
  end

  # Deletes the selected text and repositions the cursor at the selection start.
  # Returns true if a deletion was made (so callers can return early).
  private def delete_selection : Bool
    return false unless (range = selection_range)
    chars = editing_text.chars
    self.editing_text = (chars[0...range[0]] + chars[range[1]...chars.size]).join
    @cursor_pos = range[0]
    @selection_anchor = nil
    true
  end

  private def reset_blink
    @last_input_time = R.get_time
  end
end
