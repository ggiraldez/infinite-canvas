# Visual lines produced by word-wrapping.
# Each entry: {line_text, char_offset_in_full_text_string}.
alias TextLayoutData = Array({String, Int32})

module TextLayout
  # Wrap *text* to fit within *avail_width* pixels at *font_size*.
  # Returns visual line runs as {line_text, start_offset_in_text} pairs.
  # Preserves explicit newlines; breaks at word boundaries where possible.
  # The *measure* block returns the pixel width of a string at *font_size*.
  #
  # ── Algorithm (O(n) measure calls) ────────────────────────────────────────
  # Build a per-character width prefix-sum, then use binary search + one
  # interpolation pivot to find each line-break in O(log n) probes instead
  # of the naïve O(L) re-measurement per line.  See the original method
  # comment in text_element.cr for a full derivation.
  def self.compute(text : String, avail_width : Float32, font_size : Int32,
                   &measure : String -> Int32) : TextLayoutData
    avail_i     = [avail_width, 1.0_f32].max.to_i32
    result      = [] of {String, Int32}
    spacing     = font_size / 10
    full_offset = 0

    text.split('\n').each do |para|
      if para.empty?
        result << {"", full_offset}
        full_offset += 1
        next
      end

      para_chars = para.chars
      para_len   = para_chars.size

      # One measure call per character; O(n) total for the paragraph.
      char_ws = para_chars.map { |c| measure.call(c.to_s) }
      prefix  = Array(Int32).new(para_len + 1, 0)
      (0...para_len).each { |i| prefix[i + 1] = prefix[i] + char_ws[i] }

      line_start = 0

      while line_start < para_len
        remaining = para_len - line_start
        full_w    = prefix[para_len] - prefix[line_start] + spacing * (remaining - 1)

        if full_w <= avail_i
          # Everything remaining fits — emit and move to next paragraph.
          result << {para_chars[line_start, remaining].join, full_offset + line_start}
          break
        end

        # Guard: single character wider than avail — force-emit to avoid infinite loop.
        if char_ws[line_start] > avail_i
          result << {para_chars[line_start].to_s, full_offset + line_start}
          line_start += 1
          next
        end

        # ── Binary search for last_fit ─────────────────────────────────────
        lo = line_start
        hi = para_len - 1

        # Interpolation pivot for uniform-width characters (typically 0–1 extra probes).
        est = (line_start + avail_i * remaining / full_w - 1).clamp(line_start, para_len - 1).to_i32
        if prefix[est + 1] - prefix[line_start] + spacing * (est - line_start) <= avail_i
          lo = est
        else
          hi = est - 1
        end

        while lo < hi
          mid = ((lo + hi + 1) / 2).to_i32
          if prefix[mid + 1] - prefix[line_start] + spacing * (mid - line_start) <= avail_i
            lo = mid
          else
            hi = mid - 1
          end
        end
        last_fit = lo

        # ── Word-break search ──────────────────────────────────────────────
        # Include last_fit+1: a space exactly at the overflow boundary is the
        # natural break point — content before it fills the line cleanly.
        j = [last_fit + 1, para_len - 1].min
        while j >= line_start && para_chars[j] != ' '
          j -= 1
        end

        if j >= line_start
          result << {para_chars[line_start, j - line_start].join, full_offset + line_start}
          line_start = j + 1
        else
          result << {para_chars[line_start, last_fit - line_start + 1].join, full_offset + line_start}
          line_start = last_fit + 1
        end
      end

      full_offset += para_len + 1
    end

    result
  end
end
