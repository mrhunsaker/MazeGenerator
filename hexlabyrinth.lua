#!/usr/bin/env lua
--[[
===========================================================================
  hexlabyrinth.lua  —  v1.0.0
  Hexagonal grid labyrinth generator with guaranteed unique solution.
  Entrance at top, exit at bottom.

  Outputs (written to the ./mazes directory):
    mazeXXXX_hex.svg           — the blank maze (XXXX = seed)
    mazeXXXX_hex_solution.svg  — maze with the solution path highlighted
    mazeXXXX_hex.json          — all parameters (seed, path, stats) for reproducibility

  Usage:
    lua hexlabyrinth.lua

  Requirements: Lua 5.1 / 5.2 / 5.3 / 5.4 or LuaJIT
===========================================================================
--]]

-- ── Compatibility shims ───────────────────────────────────────────────────
local unpack = table.unpack or unpack
local floor  = math.floor
local function idiv(a, b) return floor(a / b) end
local sqrt3 = math.sqrt(3)

-- ── Configuration ─────────────────────────────────────────────────────────
local CFG = {
  size_mm    = 200,   -- physical size annotation (mm)
  hex_rings  = 18,    -- rings from center outward
  canvas_px  = 800,   -- SVG viewBox dimension
  wall_color  = "#1a1a2e",
  sol_color   = "#e63946",
  start_color = "#2a9d8f",
  end_color   = "#e76f51",
  bg_color    = "#f8f9fa",
}

local HEX_RINGS = CFG.hex_rings

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

-- ── Axial hex coordinates: (q, r) ─────────────────────────────────────────
-- Each hex is identified by cube coordinates (q, r, s) where q+r+s=0.
-- We store only (q, r) and compute s = -q-r implicitly.

local function hex_key(q, r)
  return q * 10000 + r
end

local function get_hex_neighbors(q, r)
  -- Six neighbors in axial coordinates
  local dirs = {
    {q+1, r},     -- E
    {q+1, r-1},   -- SE
    {q, r-1},     -- SW
    {q-1, r},     -- W
    {q-1, r+1},   -- NW
    {q, r+1},     -- NE
  }
  return dirs
end

local function hex_distance(q1, r1, q2, r2)
  return (math.abs(q1-q2) + math.abs(r1-r2) + math.abs((-q1-r1)-(-q2-r2))) / 2
end

-- ── Hex BFS ────────────────────────────────────────────────────────────────
local function hex_bfs(sq, sr, eq, er, passable)
  local function key(q, r) return hex_key(q, r) end
  local parent, vis = {}, {[key(sq, sr)]=true}
  local q_queue, qi = {{sq, sr}}, 1

  while qi <= #q_queue do
    local q, r = q_queue[qi][1], q_queue[qi][2]; qi=qi+1
    if q == eq and r == er then
      local path = {}
      while not(q == sq and r == sr) do
        table.insert(path, 1, {q, r})
        local p = parent[key(q, r)]
        q, r = p[1], p[2]
      end
      table.insert(path, 1, {sq, sr})
      return path
    end

    local neighbors = get_hex_neighbors(q, r)
    for _, neighbor in ipairs(neighbors) do
      local nq, nr = neighbor[1], neighbor[2]
      local nkey = key(nq, nr)
      if not vis[nkey] and passable(nq, nr) then
        vis[nkey] = true
        parent[nkey] = {q, r}
        table.insert(q_queue, {nq, nr})
      end
    end
  end

  return nil
end

-- ── Solution generator ────────────────────────────────────────────────────
local function generate_solution(rng)
  -- Start at center (0, 0), end at bottom (0, HEX_RINGS)
  local sq, sr = 0, 0
  local eq, er = 0, HEX_RINGS

  local function all_open(q, r)
    local s = -q - r
    return hex_distance(q, r, 0, 0) <= HEX_RINGS
  end

  local opt = hex_bfs(sq, sr, eq, er, all_open)
  local opt_len = #opt - 1
  local target_min = floor(opt_len * 1.52)

  for _=1, 10000 do
    local vis = {}
    local function vk(q, r) return hex_key(q, r) end
    vis[vk(sq, sr)] = true
    local path = {{sq, sr}}
    local at_end = false

    for _=1, HEX_RINGS * 6 * 4 do
      local q, r = path[#path][1], path[#path][2]
      if q == eq and r == er then at_end=true; break end
      local long = (#path-1) >= target_min
      local dirs = get_hex_neighbors(q, r)
      rng:shuffle(dirs)
      local moved = false

      -- Pass 1: prioritised moves
      for _, d in ipairs(dirs) do
        local nq, nr = d[1], d[2]
        if not vis[vk(nq, nr)] and all_open(nq, nr) then
          if long then
            if nq == eq and nr == er then
              table.insert(path, {nq, nr}); vis[vk(nq, nr)]=true; moved=true; break
            end
            -- Prefer moving outward
            local curr_dist = hex_distance(q, r, 0, 0)
            local next_dist = hex_distance(nq, nr, 0, 0)
            if next_dist >= curr_dist then
              table.insert(path, {nq, nr}); vis[vk(nq, nr)]=true; moved=true; break
            end
          else
            table.insert(path, {nq, nr}); vis[vk(nq, nr)]=true; moved=true; break
          end
        end
      end

      if not moved then
        rng:shuffle(dirs)
        for _, d in ipairs(dirs) do
          local nq, nr = d[1], d[2]
          if not vis[vk(nq, nr)] and all_open(nq, nr) then
            table.insert(path, {nq, nr}); vis[vk(nq, nr)]=true; moved=true; break
          end
        end
      end
      if not moved then break end
    end

    local last = path[#path]
    if at_end or (last[1] == eq and last[2] == er) then
      local sol_len = #path - 1
      if sol_len > opt_len * 1.5 then
        return path, opt_len, sol_len
      end
    end
  end

  -- Fallback: spiral outward
  local path, vis = {}, {}
  local function vk(q, r) return hex_key(q, r) end
  table.insert(path, {0, 0}); vis[vk(0, 0)] = true

  for dist=1, HEX_RINGS do
    -- Collect all hexes at this distance
    local ring_cells = {}
    for q=-dist, dist do
      for r=-dist, dist do
        if hex_distance(q, r, 0, 0) == dist then
          table.insert(ring_cells, {q, r})
        end
      end
    end
    rng:shuffle(ring_cells)
    for _, cell in ipairs(ring_cells) do
      local q, r = cell[1], cell[2]
      if not vis[vk(q, r)] then
        table.insert(path, {q, r})
        vis[vk(q, r)] = true
      end
    end
  end

  return path, opt_len, #path-1
end

-- ── Maze builder (Wilson's algorithm on hex graph) ───────────────────────
local function build_maze(rng, carving_state, solution)
  local function vk(q, r) return hex_key(q, r) end
  local function all_open(q, r)
    local s = -q - r
    return hex_distance(q, r, 0, 0) <= HEX_RINGS
  end

  -- Carve solution
  for i, cell in ipairs(solution) do
    carving_state[vk(cell[1], cell[2])] = true
    if i > 1 then
      local prev = solution[i-1]
      carving_state[vk(prev[1], prev[2]) .. ">" .. vk(cell[1], cell[2])] = true
    end
  end

  -- Collect all uncarved cells
  local uncarved = {}
  for dist=0, HEX_RINGS do
    if dist == 0 then
      if not carving_state[vk(0, 0)] then
        table.insert(uncarved, {0, 0})
      end
    else
      for q=-dist, dist do
        for r=-dist, dist do
          if hex_distance(q, r, 0, 0) == dist and not carving_state[vk(q, r)] then
            table.insert(uncarved, {q, r})
          end
        end
      end
    end
  end
  rng:shuffle(uncarved)

  -- Wilson's algorithm
  for _, start in ipairs(uncarved) do
    if not carving_state[vk(start[1], start[2])] then
      local walk = {start}
      local widx = {[vk(start[1], start[2])]=1}
      local q, r = start[1], start[2]

      for _=1, HEX_RINGS * 6 * 10 do
        if carving_state[vk(q, r)] then break end
        local dirs = get_hex_neighbors(q, r)
        rng:shuffle(dirs)
        local found = false
        for _, d in ipairs(dirs) do
          if all_open(d[1], d[2]) then
            local nq, nr = d[1], d[2]
            local k = vk(nq, nr)
            if widx[k] then
              -- Loop erasure
              local li = widx[k]
              for i=li+1,#walk do widx[vk(walk[i][1],walk[i][2])]=nil end
              while #walk>li do table.remove(walk) end
            else
              table.insert(walk, {nq, nr}); widx[k]=#walk
            end
            q, r = nq, nr
            found = true
            break
          end
        end
        if not found then break end
      end

      if carving_state[vk(q, r)] then
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

-- ── SVG renderer for hexagonal maze ───────────────────────────────────────
local function render_svg(carving_state, solution, show_solution, filepath)
  local px = CFG.canvas_px
  local cx, cy = px / 2, px / 2
  local hex_size = px / (4 + 2*HEX_RINGS)  -- approximate size for visible layout

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

  -- Convert axial hex to pixel coordinates
  local function hex_to_xy(q, r)
    local x = hex_size * (3/2 * q)
    local y = hex_size * (sqrt3/2 * q + sqrt3 * r)
    return cx + x, cy + y
  end

  -- Function to check if passage exists
  local function is_passage(q1, r1, q2, r2)
    local function vk(q, r) return hex_key(q, r) end
    return carving_state[vk(q1, r1) .. ">" .. vk(q2, r2)] or
           carving_state[vk(q2, r2) .. ">" .. vk(q1, r1)]
  end

  -- Draw hex walls as line segments
  local function all_open(q, r)
    return hex_distance(q, r, 0, 0) <= HEX_RINGS
  end

  local lw = 1.0
  for dist=0, HEX_RINGS do
    if dist == 0 then
      local neighbors = get_hex_neighbors(0, 0)
      for _, neighbor in ipairs(neighbors) do
        local nq, nr = neighbor[1], neighbor[2]
        if all_open(nq, nr) and not is_passage(0, 0, nq, nr) then
          local x1, y1 = hex_to_xy(0, 0)
          local x2, y2 = hex_to_xy(nq, nr)
          f:write(string.format(
            '  <line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%.2f"/>\n',
            x1, y1, x2, y2, CFG.wall_color, lw))
        end
      end
    else
      for q=-dist, dist do
        for r=-dist, dist do
          if hex_distance(q, r, 0, 0) == dist then
            local neighbors = get_hex_neighbors(q, r)
            for _, neighbor in ipairs(neighbors) do
              local nq, nr = neighbor[1], neighbor[2]
              if all_open(nq, nr) and not (nq > q or (nq == q and nr > r)) then
                if not is_passage(q, r, nq, nr) then
                  local x1, y1 = hex_to_xy(q, r)
                  local x2, y2 = hex_to_xy(nq, nr)
                  f:write(string.format(
                    '  <line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%.2f"/>\n',
                    x1, y1, x2, y2, CFG.wall_color, lw))
                end
              end
            end
          end
        end
      end
    end
  end

  -- Solution overlay
  if show_solution and solution then
    local line_width = 2.0
    for i=2, #solution do
      local q1, r1 = solution[i-1][1], solution[i-1][2]
      local q2, r2 = solution[i][1], solution[i][2]
      local x1, y1 = hex_to_xy(q1, r1)
      local x2, y2 = hex_to_xy(q2, r2)
      f:write(string.format(
        '  <line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%.2f" stroke-linecap="round"/>\n',
        x1, y1, x2, y2, CFG.sol_color, line_width))
    end

    -- Entry/exit markers
    if #solution > 0 then
      local sx, sy = hex_to_xy(solution[1][1], solution[1][2])
      local ex, ey = hex_to_xy(solution[#solution][1], solution[#solution][2])
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
  io.write("  Hexagonal Labyrinth Generator            \n")
  io.write(string.format("  200mm diameter  |  %d rings              \n", HEX_RINGS))
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

  io.write(string.format("\n  Seed  : %d\n  Rings : %d\n", seed_val, HEX_RINGS))

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

  local base_name = string.format("maze_%04d_hexagon", seed_val)
  local maze_file = string.format("%s/%s.svg", mazes_dir, base_name)
  local solution_file = string.format("%s/%s_solution.svg", mazes_dir, base_name)
  local params_file = string.format("%s/%s.json", mazes_dir, base_name)

  local ok1 = render_svg(carving_state, solution, false, maze_file)
  if ok1 then io.write(string.format("      %s written\n", maze_file)) end

  local ok2 = render_svg(carving_state, solution, true, solution_file)
  if ok2 then io.write(string.format("      %s written\n", solution_file)) end

  local sol_list = {}
  for _, cell in ipairs(solution) do
    table.insert(sol_list, {q=cell[1], r=cell[2]})
  end

  local ok3 = write_json(params_file, {
    generator             = "hexlabyrinth.lua",
    version               = "1.0.0",
    seed                  = seed_val,
    physical_size_mm      = CFG.size_mm,
    topology              = "hexagonal",
    hex_rings             = HEX_RINGS,
    svg_canvas_px         = CFG.canvas_px,
    start_hex_coord       = {q=0, r=0},
    end_hex_coord         = {q=0, r=HEX_RINGS},
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
