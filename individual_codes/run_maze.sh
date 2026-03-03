#!/usr/bin/env bash
# run_maze.sh — Bash / macOS / Linux entry point for labyrinth.lua
# Usage: bash run_maze.sh   (or  chmod +x run_maze.sh && ./run_maze.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LUA_SCRIPT="$SCRIPT_DIR/labyrinth.lua"

# Find a Lua interpreter
LUA=""
for cmd in lua lua5.4 lua5.3 lua5.2 lua5.1 luajit; do
  if command -v "$cmd" &>/dev/null; then
    LUA="$cmd"
    break
  fi
done

if [ -z "$LUA" ]; then
  echo "ERROR: No Lua interpreter found."
  echo "Install Lua with one of:"
  echo "  Debian/Ubuntu : sudo apt install lua5.4"
  echo "  macOS (Homebrew): brew install lua"
  echo "  Arch Linux     : sudo pacman -S lua"
  exit 1
fi

echo "Using: $($LUA -v 2>&1 | head -1)"
echo ""
"$LUA" "$LUA_SCRIPT"

# Post-process with Inkscape (SVG -> PNG -> Traced SVG)
echo ""
echo "Post-processing with Inkscape..."

# Locate Inkscape
INKSCAPE=""
if command -v inkscape &>/dev/null; then
  INKSCAPE="inkscape"
elif [ -f "/Applications/Inkscape.app/Contents/MacOS/inkscape" ]; then
  INKSCAPE="/Applications/Inkscape.app/Contents/MacOS/inkscape"
fi

if [ -z "$INKSCAPE" ]; then
  echo "WARNING: Inkscape not found. Skipping post-processing."
  echo "Install from: https://inkscape.org/release/"
  exit 0
fi

echo "Using Inkscape: $INKSCAPE"

# Process all maze SVG files in ./mazes directory
MAZES_DIR="$SCRIPT_DIR/mazes"
for svg_file in "$MAZES_DIR"/maze*.svg; do
  # Skip if file doesn't exist or is already a traced file
  [ -f "$svg_file" ] || continue
  [[ "$svg_file" == *"_traced.svg" ]] && continue
  
  base_name="$(basename "$svg_file" .svg)"
  png_file="$MAZES_DIR/$base_name.png"
  traced_file="$MAZES_DIR/${base_name}_traced.svg"
  
  echo "Processing: $(basename "$svg_file")"
  
  # Step 1: Export SVG to PNG
  echo "  -> Converting to PNG..."
  "$INKSCAPE" --export-type=png --export-filename="$png_file" "$svg_file" 2>/dev/null || true
  
  if [ ! -f "$png_file" ]; then
    echo "  ERROR: PNG export failed"
    continue
  fi
  
  # Step 2: Trace bitmap with brightness cutoff 0.5, fit to selection, save
  echo "  -> Tracing bitmap (brightness cutoff 0.5)..."
  "$INKSCAPE" \
    --export-type=svg \
    --export-filename="$traced_file" \
    --export-plain-svg \
    --actions="file-open:$png_file;EditSelectAll;selection-trace;edit-select-all-in-all-layers;fit-canvas-to-selection;export-do" \
    2>/dev/null || true
  
  if [ -f "$traced_file" ]; then
    echo "  -> Saved: $(basename "$traced_file")"
  else
    echo "  WARNING: Traced SVG not generated"
  fi
  
  # Clean up PNG
  [ -f "$png_file" ] && rm -f "$png_file"
done

echo ""
echo "Post-processing complete!"
