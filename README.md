# Infinite Canvas

> This project is being built collaboratively with [Claude](https://claude.ai/claude-code) (Anthropic's AI assistant). The architecture, features, and code are developed through an iterative conversation — Claude writes and refines the implementation while the human steers the design.

Crystal + Raylib desktop app: an infinite, pannable/zoomable canvas for
sketching diagrams and taking notes. Supports rectangles with editable labels,
plain text nodes, and directional arrows connecting elements.

## Prerequisites

- Crystal >= 1.10
- Raylib 5.0 native library
- OpenSSL development libraries (required by Crystal's UUID stdlib)

On macOS: `brew install crystal raylib openssl`
On Arch: `pacman -S crystal shards raylib openssl`

### Building Raylib 5.0 locally (Debian/Ubuntu)

If a distro package for Raylib 5.0 is not available, build it from source and
install it under the repo directory so no root access is required:

```sh
# Install build tools, Raylib's system dependencies, and OpenSSL dev headers
sudo apt-get install -y cmake libasound2-dev libx11-dev libxrandr-dev \
    libxi-dev libgl1-mesa-dev libglu1-mesa-dev libxcursor-dev libxinerama-dev \
    libssl-dev

# Clone and build Raylib 5.0
git clone --depth 1 --branch 5.0 https://github.com/raysan5/raylib
cmake raylib -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release -B raylib/build
cmake --build raylib/build

# Install into a local prefix (no sudo needed)
cmake --install raylib/build --prefix local
```

This places `libraylib.so` under `local/lib/`.

## Build & run

Inline `LIBRARY_PATH` when building so the linker finds the locally built Raylib:

```sh
shards install
LIBRARY_PATH=$PWD/local/lib shards build --release
LD_LIBRARY_PATH=$PWD/local/lib ./bin/infinite_canvas
```

When Raylib is installed system-wide (e.g. via a package manager) the environment
variables can be omitted. `env.sh` in the repo root exports both variables as a
convenience (`source env.sh`) if you prefer that workflow.

The two variables and their roles:

| Variable | Purpose |
|---|---|
| `LIBRARY_PATH` | Tells the linker where to find `-lraylib` at **compile time** |
| `LD_LIBRARY_PATH` | Tells the dynamic loader where to find `libraylib.so` at **run time** |

You can make the run-time path permanent by adding the following line to
`/etc/ld.so.conf.d/raylib.conf` (requires root) and then running `sudo ldconfig`:

```
/absolute/path/to/local/lib
```

## Controls

### Tools

Switch tools with the keyboard. The active tool is shown in the top-left HUD.

| Key | Tool | Behaviour |
|---|---|---|
| `S` | **Select** (default) | Click an element to select it; click empty space to deselect |
| `R` | **Rect** | Click to place a default-sized rectangle; drag to draw a custom size |
| `T` | **Text** | Click to place a text node; drag to set an initial size |
| `A` | **Arrow** | Drag from one element to another to create a directional connection |

After placing an element or drawing an arrow, the tool automatically returns to
Select and the new element is selected (arrows return to Select without selecting
the arrow itself).

### Arrows

Arrows connect two elements by UUID, so they track the elements as they are moved
or resized.

- **Routing style** — each arrow is independently either *Orthogonal* (rectilinear
  segments, default) or *Straight* (direct border-to-border line). Toggle with `Tab`
  while an arrow is selected.
- **Endpoint spreading** — when multiple orthogonal arrows share the same border side
  of an element, their exit/entry points are spread evenly along that side and ordered
  to minimise crossings.
- **Cascade delete** — deleting an element also removes all arrows connected to it.

### Editing

Select any rectangle or text node to start editing its content immediately.

| Action | Input |
|---|---|
| Insert character | Type while an element is selected |
| Insert newline | `Enter` |
| Delete character left of cursor | `Backspace` |
| Delete word left of cursor | `Ctrl+Backspace` |
| Move cursor | `←` / `→` / `↑` / `↓` |
| Jump by word | `Ctrl+←` / `Ctrl+→` |
| Extend selection | Hold `Shift` with any cursor movement key |
| Delete selection | `Backspace` with an active selection |
| Copy selection | `Ctrl+C` |
| Paste (replaces selection) | `Ctrl+V` |
| Delete element | `Delete` (also removes connected arrows) |
| Toggle arrow routing | `Tab` (while an arrow is selected) |

The cursor blinks after a short steady-on period following each keystroke, matching standard editor behaviour. Vertical navigation preserves the visual horizontal position across lines (sticky column), accounting for the proportional font.

### Text node word wrap

Text nodes auto-size to their content by default. They cap at **half the screen width** — once text would exceed this, it wraps automatically. To set a custom width, drag the **left or right resize handle** of a selected text node. From that point on the width is locked and text reflows to fit; the height always adjusts dynamically. Dragging the handle back or resizing larger works the same way. `↑` / `↓` navigate by visual (wrapped) lines when word wrap is active.

### Multiple selection

Drag an empty area with the Select tool to rubber-band select multiple elements. All selected elements can be moved together. Holding `Shift` snaps the move to the grid.

### Canvas navigation

| Action | Input |
|---|---|
| Move element | Drag a selected element (Select tool) |
| Resize element | Drag a handle on a selected element (Select tool) |
| Pan canvas | Right-drag or middle-drag |
| Zoom | Mouse wheel — snaps to well-known levels (0.25×, 0.5×, 1×, 2×, …) |
| Snap to grid | Hold `Shift` while moving or resizing |

The canvas is saved to `canvas.json` in the working directory on exit and
restored automatically on next launch.

### HUD

The top-left overlay shows the active tool, element count, and zoom level. When
an arrow is selected its routing style is shown with a reminder of the `Tab`
toggle. The bottom-right corner shows smoothed **update** and **draw** times (in
ms, exponential moving average over ~10 frames) alongside the FPS counter.

## Performance notes

### Viewport culling

Every frame, non-arrow elements are culled against the visible world-space rectangle before drawing. The visible rect is computed from the `Camera2D` by projecting the screen corners to world space; any element whose bounding rect does not overlap is skipped entirely. Arrow elements are exempt from culling — their bounds are `(0,0,0,0)` at construction and only updated during `draw`, so they are always rendered (they are cheap line primitives).

### Word-wrap layout (`visual_line_runs`)

Laying out wrapped text requires knowing how wide any substring is. The naive approach — calling `MeasureText` on a growing prefix at each candidate break — is O(n²) in the number of characters per paragraph.

`visual_line_runs` uses an O(n) prefix-sum to answer any substring-width query in O(1):

1. **Single-character measurements** — `MeasureText(c)` is called once per character in the paragraph and stored in `char_ws`. This is the only O(n) pass over Raylib.
2. **Prefix-sum array** — `prefix[i]` holds the sum of `char_ws[0..i-1]`. The width of the substring `s[a..b]` (using Raylib's formula, which adds `spacing` between — not after — adjacent characters) is:
   ```
   prefix[b+1] - prefix[a] + spacing * (b - a)
   ```
   where `spacing = fontSize / 10` (Raylib's default inter-character gap).
3. **Interpolation-seeded binary search** — instead of bisecting from the middle each time, the first candidate is estimated by assuming uniform character width:
   ```
   est ≈ line_start + avail_width * remaining_chars / full_remaining_width
   ```
   This places the pivot near the true answer in one step, reducing average binary search iterations to roughly O(log log n) in practice for text with homogeneous character widths. The search then converges with standard bisection.
4. **Word-break scan** — after the binary search finds `last_fit` (the last character that fits on the line), the algorithm scans rightward looking for a space to break on, including the character immediately after `last_fit` (which handles the case where the overflow position is itself a space).

The net result is O(n) per paragraph (dominated by the single-char measurement pass) regardless of line count.

## Layout

- `src/infinite_canvas.cr` — entry point, window setup, main loop, HUD
- `src/canvas.cr` — `Canvas` class skeleton: constants, enums, state, `initialize`, `save`/`load`, `update`, `draw`
- `src/canvas_input.cr` — all input handlers (`handle_pan`, `handle_zoom`, `handle_left_mouse`, `handle_text_input`, …), hit-testing, and resize geometry
- `src/canvas_drawing.cr` — drawing helpers (`draw_grid`, `draw_selection`, `draw_draft`)
- `src/element.cr` — `Element` abstract base class and `ElementData` interface
- `src/text_editing.cr` — `TextEditing` mixin: cursor, selection, word movement, clipboard
- `src/rect_element.cr` — `RectElement`: filled rectangle with centred multi-line label
- `src/text_element.cr` — `TextElement`: plain text node, auto-sized with optional word wrap
- `src/arrow_element.cr` — `ArrowElement`: orthogonal/straight routing, endpoint spreading
- `src/persistence.cr` — JSON serialisation mirror structs for save/load
