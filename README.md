# Infinite Canvas

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

When Raylib is installed system-wide (e.g. via a package manager), the standard
invocation works:

```sh
shards install
shards build --release
./bin/infinite_canvas
```

When using the locally built Raylib from `local/lib/` (see above), prefix every
`shards`/`crystal` command and the final binary with the library path:

```sh
# Build
LIBRARY_PATH=$PWD/local/lib shards build --release

# Run
LD_LIBRARY_PATH=$PWD/local/lib ./bin/infinite_canvas
```

Both variables must point to the same directory:

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

| Action | Input |
|---|---|
| Draw a rectangle | `R` to select Rect tool, then left-drag on empty space |
| Draw a text node | `T` to select Text tool, then left-drag on empty space |
| Edit label / text | Click to select, then type |
| Insert newline | Enter |
| Backspace | Delete last character |
| Delete element | Delete key |
| Move element | Drag a selected element |
| Resize element | Drag a handle on a selected element |
| Pan canvas | Right-drag or middle-drag |
| Zoom | Mouse wheel (snaps to well-known levels: 0.25×, 0.5×, 1×, 2×, …) |

The canvas is saved to `canvas.json` in the working directory on exit and
restored automatically on next launch.

## Layout

- `src/infinite_canvas.cr` — entry point, window setup, main loop, HUD
- `src/canvas.cr` — camera, grid, input handling, element management
- `src/element.cr` — `Element` base class, `RectElement`, `TextElement`
- `src/persistence.cr` — JSON serialization for save/load
