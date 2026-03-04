#!/usr/bin/env lua
--[[
===========================================================================
  roundlabyrinth.lua  —  v1.0.0
  200 mm circular labyrinth generator with concentric rings.
  Entrance at top (12 o'clock), exit at bottom (6 o'clock).

  Outputs (written to the ./mazes directory):
    mazeXXXX.svg           — the blank maze (XXXX = seed)
    mazeXXXX_solution.svg  — maze with the solution path highlighted
    mazeXXXX.json          — all parameters (seed, path, stats) for reproducibility

  Usage:
    lua roundlabyrinth.lua

  Requirements: Lua 5.1 / 5.2 / 5.3 / 5.4 or LuaJIT
===========================================================================
--]]

-- ── Compatibility shims ───────────────────────────────────────────────────
local unpack = table.unpack or unpack
local floor  = math.floor
local function idiv(a, b) return floor(a / b) end
local pi = math.pi

-- ── Configuration ─────────────────────────────────────────────────────────
local CFG = {
  size_mm       = 200,   -- outer diameter annotation (mm)
  num_rings     = 20,    -- concentric rings from center to edge
  canvas_px     = 800,   -- SVG viewBox dimension
  center_open   = true,  -- if true, center cell is open; if false, wall
  wall_color    = "#1a1a2e",
  sol_color     = "#e63946",
  start_color   = "#2a9d8f",
  end_color     = "#e76f51",
  bg_color      = "#f8f9fa",
}

local NUM_RINGS = CFG.num_rings

-- ── Seeded RNG (xoshiro128-style, pure Lua) ───────────────────────────────
local RNG = {}
RNG.__index = RNG

local function u32(n)   return n % 2^32            end
local function shr(a,n) return floor(a / 2^n)      end
local function shl(a,n) return u32(a * 2^n)        end
local function xor32(a,b)
  local r,m = 0,1
  for _=1,32 do
    if (a%2) ~= (b%2) then r=r+m end
    a=floor(a/2); b=floor(b/2); m=m*2
  end
  return r
end
local function rol32(v,n)
  n = n % 32
  return u32(shl(v,n) + shr(v,32-n))
end
local function mul32(a,b)
  local result = 0
  a = u32(a); b = u32(b)
  for i=0,31 do
    if floor(b/2^i)%2 == 1 then
      result = u32(result + u32(a * 2^i))
    end
  end
  return result
end

function RNG.new(seed)
  local function sm(v)
    v = u32(v + 0x9e3779b9)
    v = xor32(v, shr(v,16)); v = mul32(v, 0x85ebca6b)
    v = xor32(v, shr(v,13)); v = mul32(v, 0xc2b2ae35)
    v = xor32(v, shr(v,16))
    return v
  end
  local a = sm(seed); local b = sm(a)
  local c = sm(b);    local d = sm(c)
  return setmetatable({a=a,b=b,c=c,d=d}, RNG)
end

function RNG:next()
  local a,b,c,d = self.a, self.b, self.c, self.d
  local res = mul32(rol32(mul32(b, 5), 7), 9)
  local t   = shl(b, 9)
  c = xor32(c, a); d = xor32(d, b)
  b = xor32(b, c); a = xor32(a, d)
  c = xor32(c, t); d = rol32(d, 11)
  self.a, self.b, self.c, self.d = a, b, c, d
  return res
end

function RNG:randint(lo, hi)
  return lo + (self:next() % (hi - lo + 1))
end

function RNG:shuffle(t)
  for i = #t, 2, -1 do
    local j = self:randint(1, i)
    t[i], t[j] = t[j], t[i]
  end
end

-- ── Ring-based graph helpers ──────────────────────────────────────────────
-- Graph structure: ring 0 at center, ring NUM_RINGS at outer edge.
-- Each ring r (1 to NUM_RINGS) has 6*r cells numbered 0 to 6*r-1 (by angle).
-- Center (ring 0) is a single cell.
-- Adjacency: radial (same angle, adjacent ring) + tangential (same ring, adjacent angle).

local function cell_key(ring, cell)
  return ring * 10000 + cell
end

local function get_neighbors(ring, cell)
  local neighbors = {}

  -- Same ring, adjacent cells (tangential)
  if ring > 0 then
    local sz = 6 * ring
    local cw = (cell + 1) % sz
    local ccw = (cell - 1 + sz) % sz
    table.insert(neighbors, {ring, cw})
    table.insert(neighbors, {ring, ccw})
  end

  -- Adjacent rings (radial)
  if ring > 0 then
    -- Inward to ring-1
    local parent_ring = ring - 1
    if parent_ring == 0 then
      -- Only one cell in center
      table.insert(neighbors, {0, 0})
    else
      -- Map cell in ring to cells in parent ring
      local sz_curr = 6 * ring
      local sz_parent = 6 * parent_ring
      local parent_cell = floor(cell * sz_parent / sz_curr)
      table.insert(neighbors, {parent_ring, parent_cell})
    end
  end

  if ring < NUM_RINGS then
    -- Outward to ring+1
    local child_ring = ring + 1
    local sz_curr = 6 * ring
    local sz_child = 6 * child_ring
    local child_cell = floor(cell * sz_child / sz_curr)
    table.insert(neighbors, {child_ring, child_cell})
  end

  return neighbors
end

-- ── BFS on ring graph ─────────────────────────────────────────────────────
local function ring_bfs(start_r, start_c, end_r, end_c, passable)
  local function key(r, c) return cell_key(r, c) end
  local parent, vis = {}, {[key(start_r, start_c)]=true}
  local q, qi = {{start_r, start_c}}, 1

  while qi <= #q do
    local r, c = q[qi][1], q[qi][2]; qi=qi+1
    if r == end_r and c == end_c then
      local path = {}
      while not(r == start_r and c == start_c) do
        table.insert(path, 1, {r, c})
        local p = parent[key(r, c)]
        r, c = p[1], p[2]
      end
      table.insert(path, 1, {start_r, start_c})
      return path
    end

    local neighbors = get_neighbors(r, c)
    for _, neighbor in ipairs(neighbors) do
      local nr, nc = neighbor[1], neighbor[2]
      local nkey = key(nr, nc)
      if not vis[nkey] and passable(nr, nc) then
        vis[nkey] = true
        parent[nkey] = {r, c}
        table.insert(q, {nr, nc})
      end
    end
  end

  return nil
end

-- ── Solution generator ────────────────────────────────────────────────────
local function generate_solution(rng)
  local sr, sc = 0, 0  -- start at center
  local er, ec = NUM_RINGS, 0  -- end at outermost ring, bottom
  
  -- Re-center exit to bottom: for NUM_RINGS, with 6*NUM_RINGS cells total,
  -- angle 0 is at 12 o'clock, so bottom is at 3*NUM_RINGS cells offset (180°).
  if NUM_RINGS > 0 then
    ec = (3 * NUM_RINGS) % (6 * NUM_RINGS)
  end

  local function all_open(r, c) return true end
  local opt = ring_bfs(sr, sc, er, ec, all_open)
  local opt_len = #opt - 1
  local target_min = floor(opt_len * 1.52)

  for _=1, 10000 do
    local vis = {}
    local function vk(r, c) return cell_key(r, c) end
    vis[vk(sr, sc)] = true
    local path = {{sr, sc}}
    local at_end = false

    for _=1, NUM_RINGS * 6 * 4 do
      local r, c = path[#path][1], path[#path][2]
      if r == er and c == ec then at_end=true; break end
      local long = (#path-1) >= target_min
      local dirs = get_neighbors(r, c)
      rng:shuffle(dirs)
      local moved = false

      -- Pass 1: prioritised moves
      for _, d in ipairs(dirs) do
        local nr, nc = d[1], d[2]
        if not vis[vk(nr, nc)] then
          if long then
            if nr == er and nc == ec then
              table.insert(path, {nr, nc}); vis[vk(nr, nc)]=true; moved=true; break
            end
            -- Heuristic: prefer moving outward when near solution
            local curr_ring = r
            local next_ring = nr
            if next_ring > curr_ring or (next_ring == curr_ring and not moved) then
              table.insert(path, {nr, nc}); vis[vk(nr, nc)]=true; moved=true; break
            end
          else
            table.insert(path, {nr, nc}); vis[vk(nr, nc)]=true; moved=true; break
          end
        end
      end

      if not moved then
        rng:shuffle(dirs)
        for _, d in ipairs(dirs) do
          local nr, nc = d[1], d[2]
          if not vis[vk(nr, nc)] then
            table.insert(path, {nr, nc}); vis[vk(nr, nc)]=true; moved=true; break
          end
        end
      end
      if not moved then break end
    end

    local last = path[#path]
    if at_end or (last[1] == er and last[2] == ec) then
      local sol_len = #path - 1
      if sol_len > opt_len * 1.5 then
        return path, opt_len, sol_len
      end
    end
  end

  -- Fallback: spiraling outward
  local path, vis = {}, {}
  local function vk(r, c) return cell_key(r, c) end
  table.insert(path, {0, 0}); vis[vk(0, 0)] = true
  for r=1, NUM_RINGS do
    local sz = 6 * r
    for c=0, sz-1 do
      if not vis[vk(r, c)] then table.insert(path, {r, c}); vis[vk(r, c)]=true end
    end
  end
  return path, opt_len, #path-1
end

-- ── Maze builder (Wilson's algorithm on ring graph) ─────────────────────
local function build_maze(rng, carving_state, solution)
  local function vk(r, c) return cell_key(r, c) end

  -- Carve solution
  for i, cell in ipairs(solution) do
    carving_state[vk(cell[1], cell[2])] = true
    if i > 1 then
      local prev = solution[i-1]
      carving_state[vk(prev[1], prev[2]) .. ">" .. vk(cell[1], cell[2])] = true
    end
  end

  -- Collect all uncarved cells
  local uncarved = {{0, 0}}
  for r=1, NUM_RINGS do
    local sz = 6 * r
    for c=0, sz-1 do
      if not carving_state[vk(r, c)] then
        table.insert(uncarved, {r, c})
      end
    end
  end
  rng:shuffle(uncarved)

  -- Wilson's algorithm
  for _, start in ipairs(uncarved) do
    if not carving_state[vk(start[1], start[2])] then
      local walk = {start}
      local widx = {[vk(start[1], start[2])]=1}
      local r, c = start[1], start[2]

      for _=1, NUM_RINGS * 6 * 10 do
        if carving_state[vk(r, c)] then break end
        local dirs = get_neighbors(r, c)
        rng:shuffle(dirs)
        local nr, nc = dirs[1][1], dirs[1][2]

        local k = vk(nr, nc)
        if widx[k] then
          -- Loop erasure
          local li = widx[k]
          for i=li+1,#walk do widx[vk(walk[i][1],walk[i][2])]=nil end
          while #walk>li do table.remove(walk) end
        else
          table.insert(walk, {nr, nc}); widx[k]=#walk
        end
        r, c = nr, nc
      end

      if carving_state[vk(r, c)] then
        for i=1, #walk do
          carving_state[vk(walk[i][1], walk[i][2])] = true
          if i > 1 then
            local prev = walk[i-1]
            carving_state[vk(prev[1], prev[2]) .. ">" .. vk(walk[i][1], walk[i][2])] = true
          end
        end
      end
    end
  end
end

-- ── SVG renderer for circular maze ────────────────────────────────────────
local function render_svg(carving_state, solution, show_solution, filepath)
  local px = CFG.canvas_px
  local cx, cy = px / 2, px / 2
  local max_radius = px / 2 - 10

  local f = io.open(filepath, "w")
  if not f then
    io.stderr:write(string.format("ERROR: cannot write '%s'\n", filepath))
    return false
  end

  f:write('<?xml version="1.0" encoding="UTF-8"?>\n')
  f:write(string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" '..
    'width="%dmm" height="%dmm" viewBox="0 0 %.2f %.2f">\n',
    CFG.size_mm, CFG.size_mm, px, px))

  f:write(string.format(
    '  <rect width="%.2f" height="%.2f" fill="%s"/>\n', px, px, CFG.bg_color))

  -- Draw rings and walls as line segments
  local function cell_to_angle(ring, cell)
    if ring == 0 then return 0 end
    local sz = 6 * ring
    return (cell / sz) * 2 * pi - pi/2  -- 0 is at top
  end

  local function cell_to_xy(ring, cell)
    local r = (ring / NUM_RINGS) * max_radius
    local angle = cell_to_angle(ring, cell)
    return cx + r * math.cos(angle), cy + r * math.sin(angle)
  end

  -- Function to check if passage exists between two cells
  local function is_passage(r1, c1, r2, c2)
    local function vk(r, c) return cell_key(r, c) end
    return carving_state[vk(r1, c1) .. ">" .. vk(r2, c2)] or
           carving_state[vk(r2, c2) .. ">" .. vk(r1, c1)]
  end

  -- Draw walls as line segments between unconnected neighboring cells
  local lw = 1.5
  for ring=0, NUM_RINGS do
    local sz = (ring == 0) and 1 or 6 * ring
    for cell=0, sz-1 do
      local neighbors = get_neighbors(ring, cell)
      local function vk(r, c) return cell_key(r, c) end
      
      for _, neighbor in ipairs(neighbors) do
        local nr, nc = neighbor[1], neighbor[2]
        -- Only draw if not already drawn (avoid duplicates)
        if not (nr < ring or (nr == ring and nc < cell)) then
          if not is_passage(ring, cell, nr, nc) then
            local x1, y1 = cell_to_xy(ring, cell)
            local x2, y2 = cell_to_xy(nr, nc)
            f:write(string.format(
              '  <line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%.2f"/>\n',
              x1, y1, x2, y2, CFG.wall_color, lw))
          end
        end
      end
    end
  end

  -- Solution overlay
  if show_solution and solution then
    local line_width = 2.0
    for i=2, #solution do
      local r1, c1 = solution[i-1][1], solution[i-1][2]
      local r2, c2 = solution[i][1], solution[i][2]
      local x1, y1 = cell_to_xy(r1, c1)
      local x2, y2 = cell_to_xy(r2, c2)
      f:write(string.format(
        '  <line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%.2f" stroke-linecap="round"/>\n',
        x1, y1, x2, y2, CFG.sol_color, line_width))
    end

    -- Entry/exit markers
    if #solution > 0 then
      local sx, sy = cell_to_xy(solution[1][1], solution[1][2])
      local ex, ey = cell_to_xy(solution[#solution][1], solution[#solution][2])
      f:write(string.format(
        '  <circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"/>\n',
        sx, sy, 4, CFG.start_color))
      f:write(string.format(
        '  <circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"/>\n',
        ex, ey, 4, CFG.end_color))
    end
  end

  f:write('</svg>\n')
  f:close()
  return true
end

-- ── Minimal JSON serialiser ───────────────────────────────────────────────
local function to_json(val, depth)
  depth = depth or 0
  local t = type(val)
  if t=="number"  then return tostring(val)
  elseif t=="boolean" then return tostring(val)
  elseif t=="string"  then
    return '"'..val:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n')..'"'
  elseif t=="table" then
    local pad  = string.rep("  ", depth+1)
    local cpad = string.rep("  ", depth)
    if #val > 0 then
      local items = {}
      for _,v in ipairs(val) do table.insert(items, pad..to_json(v,depth+1)) end
      return "[\n"..table.concat(items,",\n").."\n"..cpad.."]"
    else
      local keys={}; for k in pairs(val) do table.insert(keys,k) end
      table.sort(keys)
      local items={}
      for _,k in ipairs(keys) do
        table.insert(items, pad..'"'..k..'": '..to_json(val[k],depth+1))
      end
      return "{\n"..table.concat(items,",\n").."\n"..cpad.."}"
    end
  end
  return "null"
end

local function write_json(filepath, data)
  local f = io.open(filepath, "w")
  if not f then
    io.stderr:write(string.format("ERROR: cannot write '%s'\n", filepath))
    return false
  end
  f:write(to_json(data).."\n")
  f:close()
  return true
end

-- ── Main ──────────────────────────────────────────────────────────────────
local function main()
  io.write("============================================\n")
  io.write("  Round Labyrinth Generator                \n")
  io.write(string.format("  200mm diameter  |  %d rings              \n", NUM_RINGS))
  io.write("============================================\n")

  -- Seed input
  local seed_val
  while true do
    io.write("\nEnter random seed (>=3 digit integer): ")
    io.flush()
    local line = io.read("l")
    if line == nil then io.stderr:write("No input received.\n"); os.exit(1) end
    line = line:match("^%s*(.-)%s*$")
    if line:match("^%d+$") and #line >= 3 then
      seed_val = tonumber(line)
      break
    end
    io.write("  Invalid. Please enter an integer with at least 3 digits.\n")
  end

  io.write(string.format("\n  Seed  : %d\n  Rings : %d\n", seed_val, NUM_RINGS))

  local rng = RNG.new(seed_val)
  local carving_state = {}

  -- Step 1: Solution
  io.write("[1/4] Generating random-walk solution path... ")
  io.flush()
  local solution, opt_len, sol_len = generate_solution(rng)
  local pct = (sol_len/opt_len - 1) * 100
  io.write("done\n")
  io.write(string.format("      Optimal : %d steps\n", opt_len))
  io.write(string.format("      Solution: %d steps (+%.1f%% longer)\n", sol_len, pct))

  -- Step 2: Maze
  io.write("[2/4] Building maze (Wilson's algorithm)...  ")
  io.flush()
  build_maze(rng, carving_state, solution)
  io.write("done\n")

  -- Step 3: Output
  io.write("[3/4] Writing output files...\n")

  local mazes_dir = "mazes"
  os.execute(string.format('if not exist "%s" mkdir "%s" 2>nul || mkdir -p "%s" 2>/dev/null', mazes_dir, mazes_dir, mazes_dir))

  local base_name = string.format("maze_%04d_circle", seed_val)
  local maze_file = string.format("%s/%s.svg", mazes_dir, base_name)
  local solution_file = string.format("%s/%s_solution.svg", mazes_dir, base_name)
  local params_file = string.format("%s/%s.json", mazes_dir, base_name)

  local ok1 = render_svg(carving_state, solution, false, maze_file)
  if ok1 then io.write(string.format("      %s written\n", maze_file)) end

  local ok2 = render_svg(carving_state, solution, true, solution_file)
  if ok2 then io.write(string.format("      %s written\n", solution_file)) end

  local sol_list = {}
  for _, cell in ipairs(solution) do
    table.insert(sol_list, {ring=cell[1], cell=cell[2]})
  end

  local ok3 = write_json(params_file, {
    generator             = "roundlabyrinth.lua",
    version               = "1.0.0",
    seed                  = seed_val,
    physical_size_mm      = CFG.size_mm,
    topology              = "round",
    num_rings             = NUM_RINGS,
    svg_canvas_px         = CFG.canvas_px,
    start_ring_cell       = {ring=0, cell=0},
    end_ring_cell         = {ring=NUM_RINGS, cell=idiv(3*NUM_RINGS, 1)},
    optimal_path_steps    = opt_len,
    solution_path_steps   = sol_len,
    solution_overhead_pct = floor(pct * 10) / 10,
    solution_path         = sol_list,
    outputs               = {
      maze_svg    = maze_file,
      solution_svg= solution_file,
      params_json = params_file,
    },
  })
  if ok3 then io.write(string.format("      %s written\n", params_file)) end

  io.write(string.format("\n[4/4] Done! All output files written to %s/\n", mazes_dir))
end

main()
