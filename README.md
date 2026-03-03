
# MazeGenerator

MazeGenerator is an automated pipeline for generating, visualizing, and 3D-printing unique, solvable mazes. It supports batch generation, SVG/PNG/BMP export, vector tracing, and STL model creation for 3D printing. All outputs are organized by seed in a dedicated mazes directory, with robust error handling and reproducibility.

## What This Project Does

- Generates 2D SVG mazes and solution paths from a random seed (via Lua)
- Converts SVGs to PNG/BMP for visualization and tracing
- Uses potrace to vectorize bitmaps for clean 3D extrusion
- Automates STL model generation from traced SVGs using OpenSCAD
- Supports batch processing of multiple seeds with a single command
- Ensures all filenames use integer seed formatting for compatibility
- Handles errors and seed limits robustly (int32 max)
- All outputs are reproducible and organized in ./mazes and ./mazes/stl_files

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for details.


Generates a **200 × 200 mm** square labyrinth with a guaranteed unique solution.

## Features

| # | Feature |
|---|---------|
| 1 | Start always at **top-left**, end always at **bottom-right** |
| 2 | Solution generated first via a **seeded random walk** (reproducible) |
| 3 | Solution path is **> 50 % longer** than the shortest possible path |
| 4 | Entry and exit **stubs ≥ 1 cm** are opened on the boundary |
| 5 | Remaining cells filled with **Wilson's loop-erased random walk** |
| 6 | Algorithmic verification ensures the solution path is **the only path** |
| 7 | Outputs: `maze.svg`, `maze_solution.svg`, `maze_params.json` |



## Quick Start

### Bash / macOS / Linux
```bash
bash run_maze.sh
```

### Windows Command Prompt
```cmd
run_maze.cmd
```


### PowerShell (Windows / cross-platform)
```powershell
.\pipeline.ps1
# If blocked by execution policy:
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

When running `pipeline.ps1`, you will be prompted:

* If you want to use the next 10 available seed values (not already present in the `mazes` directory), enter `Y`.
* If you enter `N`, you will be prompted to enter your own 10 seed values (integers from 100 to 2147483647, separated by commas).
* The pipeline will then generate all maze files, trace bitmaps, and create STL files automatically.

### Direct Lua call
```bash
lua labyrinth.lua
```


When prompted, enter any **integer with at least 3 digits** (e.g. `42819`).

---

## Outputs

| File | Description |
|------|-------------|
| `maze.svg` | Clean maze, no solution shown |
| `maze_solution.svg` | Maze with solution path in red, start (teal) and end (orange) marked |
| `maze_params.json` | Seed, grid size, path lengths, full solution coordinate list |


All files are written to the **mazes** directory for easy organization. STL files are placed in **mazes/stl_files**.

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


Edit the `CFG` table near the top of `labyrinth.lua`:

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
