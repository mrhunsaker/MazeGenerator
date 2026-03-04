
# MazeGenerator

MazeGenerator is an automated pipeline for generating, visualizing, and 3D-printing unique, solvable mazes in multiple topologies. It supports batch generation, SVG/PNG/BMP export, vector tracing, and STL model creation for 3D printing. All outputs are organized by seed in a dedicated mazes directory, with robust error handling and reproducibility.

## What This Project Does

- **Batch generation** of 2D SVG mazes from multiple random seeds (via Lua)
- **Multiple maze topologies**: square (traditional), round (circular), and hexagonal
- Solution paths generated first via seeded random walk (fully reproducible)
- Converts SVGs to PNG/BMP for visualization and tracing
- Uses potrace to vectorize bitmaps for clean 3D extrusion
- Automates STL model generation from traced SVGs using OpenSCAD
- Supports batch processing of 1–1000+ mazes with a single command
- Ensures all filenames use integer seed formatting for compatibility
- Handles errors and seed limits robustly (int32 max)
- All outputs are reproducible and organized in `./mazes` and `./mazes/stl_files`

## Maze Types

| Type | Generator | Dimensions | Entry | Exit | Notes |
|------|-----------|------------|-------|------|-------|
| **Square** | `labyrinth.lua` | 200 × 200 mm | Top-left | Bottom-right | Traditional 19×19 cell grid |
| **Round** | `roundlabyrinth.lua` | 200 mm ∅ | Top (12 o'clock) | Bottom (6 o'clock) | Circular maze with concentric rings |
| **Hexagonal** | `hexlabyrinth.lua` | 200 mm ∅ | Top (12 o'clock) | Bottom (6 o'clock) | Hexagonal grid topology |

All maze types output shape-specific files per seed using this pattern:
- `maze_0100_square.*`
- `maze_0100_circle.*`
- `maze_0100_hexagon.*`

## Key Features

| # | Feature |
|---|---------|
| 1 | **Batch processing**: Generate 1–∞ mazes in one command |
| 2 | **Seeded reproducibility**: Same seed → identical maze every time |
| 3 | **Unique solutions**: Solution path verified as the only path through maze |
| 4 | **Solution overhead**: Path lengths targeted >50% longer than shortest route |
| 5 | **Wilson's algorithm**: Remaining cells filled with perfect spanning tree |
| 6 | **Entry/exit stubs**: ≥1 cm boundaries on all maze types for 3D printing |
| 7 | **Multiple exports**: SVG, PNG, BMP, JSON parameters, and STL ready |

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for details.



## Quick Start

### Batch Generation (Recommended)

The **`pipeline.ps1`** script automates the entire workflow: maze generation → image export → vector tracing → STL creation.

### All Shapes Per Seed (New)

The **`allshape_pipeline.ps1`** script generates **three maze types** (square, circle, hexagon) for **each seed** you specify. This is the recommended approach for comprehensive maze generation.

**What it does:**
- Runs all three Lua generators (labyrinth, roundlabyrinth, hexlabyrinth) per seed
- Exports PNG/BMP via Inkscape
- Traces BMPs to clean SVG vectors via potrace  
- Generates STL files for 3D printing via OpenSCAD
- Creates all outputs: `.svg`, `_solution.svg`, `_traced.svg`, `.json`, `.png`, `.bmp`, `.stl`

**Quick start:**
```powershell
.\allshape_pipeline.ps1
# Prompts:
#   1) How many seed values? (enter any number: 5, 10, 100...)
#   2) Use next available seeds? (Y/N)
```

**Command-line usage:**
```powershell
# Use specific seeds
.\allshape_pipeline.ps1 -Seeds 100,101,102,103,104

# Auto-select next N unused seeds (interactive)
.\allshape_pipeline.ps1
```

**Time estimates per seed (all 3 shapes):**
- Single seed: ~30-60 seconds
- 10 seeds: ~5-10 minutes  
- 100 seeds: ~50-100 minutes

**Output for seed 0100:**
```
mazes/
  maze_0100_square.svg/.json/.png/.bmp/_solution.svg/_traced.svg
  maze_0100_circle.svg/.json/.png/.bmp/_solution.svg/_traced.svg
  maze_0100_hexagon.svg/.json/.png/.bmp/_solution.svg/_traced.svg
stl_files/
  maze_0100_square.stl
  maze_0100_circle.stl
  maze_0100_hexagon.stl
```

**Total: 21 files per seed** (7 files × 3 shapes)

#### PowerShell (Windows / cross-platform)
```powershell
# Run the full pipeline
.\pipeline.ps1

# If you get execution policy errors:
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

**Pipeline prompts:**
1. **How many mazes?** Enter any number (1–2000+)
2. **Auto-seed or custom?** 
   - `Y` → Use next N unused seeds (100, 101, 102, …)
   - `N` → Enter custom seed values as comma-separated integers

**Example:**
```
Maze Count: 50
Use next 50 available seed values? (Y/N): Y
→ Generates:
  maze_0100_square.*, maze_0100_circle.*, maze_0100_hexagon.*
  ...through seed 0149 with traced, PNG, BMP, and STL outputs
```

#### Batch Generation (manual steps)

For fine-grained control, run each step independently:

```powershell
# Step 1: Generate 100 mazes
.\batch_run_maze.ps1 -Seeds 100,101,102,103,104,105 # ... or use pipeline.ps1

# Step 2: Trace bitmaps to vectors (requires potrace)
potrace .\mazes\*.bmp -s --flat -o ".\mazes\{name}_traced.svg"

# Step 3: Generate STL files from traced SVGs
.\create_stl.ps1
```

### Single Maze Generation

#### Interactive prompt (any platform)
```bash
lua labyrinth.lua
```
When prompted, enter a seed value with at least 3 digits (e.g., `42819`).

#### With specific maze type
```bash
# Square maze (traditional)
lua labyrinth.lua

# Round maze (circular)
lua roundlabyrinth.lua

# Hexagonal maze
lua hexlabyrinth.lua
```

#### Bash / macOS / Linux
```bash
bash run_maze.sh
```

#### Windows Command Prompt
```cmd
run_maze.cmd
```

---

## Outputs

| File | Description |
|------|-------------|
| `maze_####_<shape>.svg` | Clean maze, no solution shown |
| `maze_####_<shape>_solution.svg` | Maze with solution path in red, start (teal) and end (orange) marked |
| `maze_####_<shape>_traced.svg` | Vector-traced version (after potrace) for 3D usage |
| `maze_####_<shape>.json` | Seed, topology, grid/ring settings, path lengths, full solution list |
| `maze_####_<shape>.stl` | 3D-printable STL model (via OpenSCAD) |

All files are organized by seed in the **`mazes/`** directory. STL files are placed in **`mazes/stl_files/`**.

**Example file list for seed 0100:**
```
mazes/
  maze_0100_square.svg
  maze_0100_square_solution.svg
  maze_0100_square_traced.svg
  maze_0100_square.json
  maze_0100_circle.svg
  maze_0100_circle_solution.svg
  maze_0100_circle_traced.svg
  maze_0100_circle.json
  maze_0100_hexagon.svg
  maze_0100_hexagon_solution.svg
  maze_0100_hexagon_traced.svg
  maze_0100_hexagon.json
stl_files/
  maze_0100_square.stl
  maze_0100_circle.stl
  maze_0100_hexagon.stl
```

---

## Reproducibility

Run again with the same seed → identical maze every time.  
The `maze_params.json` file records every parameter needed to reproduce the output.

---


## Requirements

- **Lua 5.1, 5.2, 5.3, 5.4, or LuaJIT** — no external libraries needed.

### Installing Lua

| Platform | Command |
|----------|---------|
| Debian / Ubuntu | `sudo apt install lua5.4` |
| macOS (Homebrew) | `brew install lua` |
| Windows (Scoop) | `scoop install lua` |
| Windows (Chocolatey) | `choco install lua` |
| Windows (Winget) | `winget install Lua.Lua` |
| Manual | https://luabinaries.sourceforge.net/ |

---



## Pipeline Overview

1. Generate maze SVGs and JSON with labyrinth.lua (seeded, reproducible)
2. Convert SVGs to PNG/BMP for visualization and tracing
3. Trace BMPs to SVG with potrace for clean vector paths
4. Generate STL files from traced SVGs using OpenSCAD
5. All steps can be run in batch via pipeline.ps1

```
1. BFS on fully-open grid → measure optimal path length
2. Seeded random walk from start → end, targeting length > 150% of optimal
3. Carve solution path into thick-grid representation
4. Open entry/exit border stubs (≥ 1 cell = ≈ 1 cm at 19×19 grid)
5. Wilson's loop-erased random walk fills all remaining uncarved cells
   → produces a perfect spanning tree (unique path between any two cells)
6. BFS verification loop seals any spurious shortcuts
7. Render thick-grid to SVG; emit JSON parameter record
```

---


## Contributing

Contributions are welcome! To contribute:

1. Fork the repository and create your branch from `main`.
2. Ensure your code follows the existing style and includes clear comments.
3. Add or update tests and documentation as needed.
4. Submit a pull request describing your changes and why they improve the project.

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.

---

## Configuration

### Square Maze (`labyrinth.lua`)

Edit the `CFG` table at the top of `labyrinth.lua`:

```lua
local CFG = {
  size_mm    = 200,   -- physical size annotation in SVG
  grid_cells = 19,    -- N×N cells (try 15, 21, 25 …)
  canvas_px  = 760,   -- SVG pixel canvas size
  wall_color  = "#1a1a2e",
  sol_color   = "#e63946",
  start_color = "#2a9d8f",
  end_color   = "#e76f51",
  bg_color    = "#f8f9fa",
}
```

### Round Maze (`roundlabyrinth.lua`)

Edit the `CFG` table at the top of `roundlabyrinth.lua`:

```lua
local CFG = {
  size_mm       = 200,   -- outer diameter in SVG annotation
  num_rings     = 20,    -- concentric rings from center to edge
  canvas_px     = 800,   -- SVG pixel canvas size
  center_open   = true,  -- open center cell or wall
  wall_color    = "#1a1a2e",
  sol_color     = "#e63946",
  start_color   = "#2a9d8f",
  end_color     = "#e76f51",
  bg_color      = "#f8f9fa",
}
```

**Features:**
- Entrance at top (12 o'clock) → exit at bottom (6 o'clock)
- Concentric ring topology instead of grid cells
- Solution path spirals outward/inward through rings
- Same reproducibility and uniqueness guarantees as square mazes

### Hexagonal Maze (`hexlabyrinth.lua`)

Edit the `CFG` table at the top of `hexlabyrinth.lua`:

```lua
local CFG = {
  size_mm     = 200,   -- physical size annotation in SVG
  hex_rings   = 18,    -- rings from center outward
  canvas_px   = 800,   -- SVG pixel canvas size
  wall_color  = "#1a1a2e",
  sol_color   = "#e63946",
  start_color = "#2a9d8f",
  end_color   = "#e76f51",
  bg_color    = "#f8f9fa",
}
```

**Features:**
- Hexagonal grid topology (6 neighbors per cell instead of 4)
- Entrance at top → exit at bottom
- Naturally suited for 3D printing with hexagonal extrusions
- Same reproducibility and uniqueness guarantees
