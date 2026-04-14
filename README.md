# Infinite Canvas

> This project is being built collaboratively with [Claude](https://claude.ai/claude-code) (Anthropic's AI assistant). The architecture, features, and code are developed through an iterative conversation — Claude writes and refines the implementation while the human steers the design.

Crystal + Raylib desktop app: an infinite, pannable/zoomable canvas for
sketching diagrams and taking notes. Supports rectangles with editable labels
and plain text nodes.

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

Source `env.sh` to set the library paths, then use the standard shards commands:

```sh
source env.sh
shards install
shards build --release
./bin/infinite_canvas
```

When Raylib is installed system-wide (e.g. via a package manager) the `source
env.sh` step can be skipped.

Both variables in `env.sh` point to the locally built Raylib:

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
| `S` | **Select** (default) | Click an element to select it; click empty space to deselect; drag reserved for future multi-select |
| `R` | **Rect** | Click to place a default-sized rectangle; drag to draw a custom size |
| `T` | **Text** | Click to place a text node; drag to set an initial size |

After placing an element with Rect or Text, the tool automatically returns to
Select and the new element is selected.

### Editing

| Action | Input |
|---|---|
| Edit label / text | Select an element, then type |
| Insert newline | `Enter` |
| Delete last character | `Backspace` |
| Delete element | `Delete` |

### Canvas navigation

| Action | Input |
|---|---|
| Move element | Drag a selected element (Select tool) |
| Resize element | Drag a handle on a selected rectangle (Select tool) |
| Pan canvas | Right-drag or middle-drag |
| Zoom | Mouse wheel — snaps to well-known levels (0.25×, 0.5×, 1×, 2×, …) |

The canvas is saved to `canvas.json` in the working directory on exit and
restored automatically on next launch.

## Layout

- `src/infinite_canvas.cr` — entry point, window setup, main loop, HUD
- `src/canvas.cr` — camera, grid, input handling, element management
- `src/element.cr` — `Element` base class, `RectElement`, `TextElement`
- `src/persistence.cr` — JSON serialization for save/load
