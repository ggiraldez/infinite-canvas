require "spec"
require "../src/text_layout"

# Measurer: 10 px per character, font-size-independent.
# font_size=0 → spacing = 0/10 = 0, so capacity = floor(avail_width / 10) chars.
# avail_width=50  → 5 chars fit  (5*10=50 ≤ 50)
# avail_width=30  → 3 chars fit
# avail_width=9   → 0 chars fit  (guard triggers: 1*10=10 > 9)
private def layout(text : String, avail : Float32, font_size : Int32 = 0)
  TextLayout.compute(text, avail, font_size) { |s| s.size * 10 }
end

describe TextLayout do
  # ── Single empty paragraph ─────────────────────────────────────────────────

  it "returns one empty entry for an empty string" do
    layout("", 100.0).should eq [{"", 0}]
  end

  # ── No wrapping needed ─────────────────────────────────────────────────────

  it "returns one entry when text fits entirely" do
    layout("hi", 100.0).should eq [{"hi", 0}]
  end

  it "fits text that exactly fills the available width" do
    # "hello" = 5 chars × 10px = 50px = avail → fits on one line
    layout("hello", 50.0).should eq [{"hello", 0}]
  end

  # ── Word-break wrapping ────────────────────────────────────────────────────

  it "breaks at a space when a line overflows" do
    # "hello world" = 11 chars, avail 50 → fits 5; break at the space (index 5)
    layout("hello world", 50.0).should eq [{"hello", 0}, {"world", 6}]
  end

  it "breaks at the rightmost fitting space" do
    # "one two three", avail 50 → 5 chars fit
    # "one t" → break before 'w' → search back → space at 3
    # "two t" → break before 'h' → space at 7 → "two"
    # "three" → fits (5 chars)
    layout("one two three", 50.0).should eq [{"one", 0}, {"two", 4}, {"three", 8}]
  end

  it "breaks at a space that falls exactly at the overflow boundary" do
    # avail 60 → fits 6 chars; last_fit=5 (the space itself at index 5)
    # word-break scan finds the space → emits "hello", then "world"
    layout("hello world", 60.0).should eq [{"hello", 0}, {"world", 6}]
  end

  # ── Character-break wrapping (no spaces) ──────────────────────────────────

  it "breaks mid-word when there is no space to break at" do
    # "hello", avail 30 → 3 chars fit; no space → hard break
    layout("hello", 30.0).should eq [{"hel", 0}, {"lo", 3}]
  end

  it "applies multiple hard breaks for a long unbreakable word" do
    layout("abcdef", 30.0).should eq [{"abc", 0}, {"def", 3}]
  end

  # ── Guard: single character wider than avail ───────────────────────────────

  it "force-emits one character per line when each char exceeds avail" do
    # avail 9 → avail_i=9; char width=10 > 9 → guard fires for every char
    layout("abc", 9.0).should eq [{"a", 0}, {"b", 1}, {"c", 2}]
  end

  # ── Explicit newlines (multiple paragraphs) ────────────────────────────────

  it "treats explicit newlines as paragraph breaks when text fits" do
    layout("hi\nbye", 100.0).should eq [{"hi", 0}, {"bye", 3}]
  end

  it "preserves an empty paragraph from a double newline" do
    layout("a\n\nb", 100.0).should eq [{"a", 0}, {"", 2}, {"b", 3}]
  end

  it "preserves a leading newline as an empty first paragraph" do
    layout("\nhello", 100.0).should eq [{"", 0}, {"hello", 1}]
  end

  it "preserves a trailing newline as an empty final paragraph" do
    layout("hello\n", 100.0).should eq [{"hello", 0}, {"", 6}]
  end

  # ── Offset tracking ────────────────────────────────────────────────────────

  it "offsets the second paragraph past the first paragraph and its newline" do
    # "abc\nde": "abc"=3 chars + 1 newline → "de" starts at offset 4
    layout("abc\nde", 100.0).should eq [{"abc", 0}, {"de", 4}]
  end

  it "offsets correctly across three paragraphs" do
    # "ab\ncd\nef": offsets 0, 3, 6
    layout("ab\ncd\nef", 100.0).should eq [{"ab", 0}, {"cd", 3}, {"ef", 6}]
  end

  it "accounts for empty paragraphs in the offset count" do
    # "a\n\nb": "a"(1) + \n(1) + \n(1) → "b" at offset 3
    layout("a\n\nb", 100.0).should eq [{"a", 0}, {"", 2}, {"b", 3}]
  end

  it "carries the correct offset into a second paragraph that itself wraps" do
    # "ab cd\nef": avail 20 → 2 chars fit
    # para 1 "ab cd": "ab" at 0, "cd" at 3; para contributes 5+1=6 to offset
    # para 2 "ef": starts at offset 6
    layout("ab cd\nef", 20.0).should eq [{"ab", 0}, {"cd", 3}, {"ef", 6}]
  end

  it "carries the correct offset when first paragraph is a single wrapped line" do
    # "hello\nworld": avail 30 fits 3 chars
    # "hello" → "hel"(0), "lo"(3); para contributes 5+1=6 to offset
    # "world" → "wor"(6), "ld"(9)
    layout("hello\nworld", 30.0).should eq [{"hel", 0}, {"lo", 3}, {"wor", 6}, {"ld", 9}]
  end

  # ── Spacing (font_size > 0) ────────────────────────────────────────────────

  it "reduces per-line capacity when inter-character spacing is non-zero" do
    # font_size=10 → spacing=1; capacity: 11N-1 ≤ avail
    # avail=54: 11*5-1=54 fits 5 chars; 11*6-1=65 does not
    # "hello world" (11 chars) → same break point as spacing=0 at avail=54
    result = TextLayout.compute("hello world", 54.0, 10) { |s| s.size * 10 }
    result.should eq [{"hello", 0}, {"world", 6}]
  end

  it "tightens the break point compared to no spacing" do
    # With spacing=0, avail=60 fits 6 chars → "hello " would fit and no wrap occurs.
    # With spacing=1 (font_size=10), 11*6-1=65 > 60 → still breaks at 5 chars.
    # Demonstrate: "abcdef" with no space, avail=60, font_size=10 → breaks at 5 chars
    result = TextLayout.compute("abcdef", 60.0, 10) { |s| s.size * 10 }
    result.should eq [{"abcde", 0}, {"f", 5}]
  end
end
