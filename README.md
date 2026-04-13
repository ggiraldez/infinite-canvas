# Infinite Canvas

Crystal + Raylib desktop app: an infinite, pannable/zoomable canvas where you
can drop elements. Phase 1 supports drawing rectangles.

## Prerequisites

- Crystal >= 1.10
- Raylib 5.0 native library

On macOS: `brew install crystal raylib`
On Arch: `pacman -S crystal shards raylib`

### Building Raylib 5.0 locally (Debian/Ubuntu)

If a distro package for Raylib 5.0 is not available, build it from source and
install it under the repo directory so no root access is required:

```sh
# Install build tools and Raylib's system dependencies
sudo apt-get install -y cmake libasound2-dev libx11-dev libxrandr-dev \
    libxi-dev libgl1-mesa-dev libglu1-mesa-dev libxcursor-dev libxinerama-dev

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

- **Left-drag on empty space** — draw a rectangle
- **Click a rectangle** — select it
- **Drag a selected rectangle** — move it
- **Drag a handle on a selected rectangle** — resize it
- **Delete / Backspace** — delete the selected rectangle
- **Right-drag / Middle-drag** — pan the canvas
- **Mouse wheel** — zoom toward the cursor

Shapes are saved to `canvas.json` in the working directory on exit and restored
automatically on next launch.

## Layout

- `src/infinite_canvas.cr` — entry point, window + main loop
- `src/canvas.cr` — camera, grid, input, draft rendering
- `src/element.cr` — `Element` base class and `RectElement`
- `src/persistence.cr` — JSON serialization structs for save/load

Next elements to add: text boxes, markdown docs, images, lines, arrows.
