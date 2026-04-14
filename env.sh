# Raylib library path for the locally-built Raylib under local/lib/
# LIBRARY_PATH  — tells the linker where to find -lraylib at compile time
# LD_LIBRARY_PATH — tells the dynamic loader where to find libraylib.so at run time
export LIBRARY_PATH=$PWD/local/lib
export LD_LIBRARY_PATH=$PWD/local/lib
