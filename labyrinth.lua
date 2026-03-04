#!/usr/bin/env lua
--[[
===========================================================================
  labyrinth.lua  —  v1.0.0
  200 × 200 mm square labyrinth generator with guaranteed unique solution.

  Outputs (written to the ./mazes directory):
    mazeXXXX.svg           — the blank maze (XXXX = seed)
    mazeXXXX_solution.svg  — maze with the solution path highlighted
    mazeXXXX.json          — all parameters (seed, path, stats) for reproducibility

  Usage:
    lua labyrinth.lua

  Wrapper entry points provided alongside this file:
    run_maze.sh   (Bash / macOS / Linux)
    run_maze.cmd  (Windows Command Prompt)
    run_maze.ps1  (PowerShell)

  Requirements: Lua 5.1 / 5.2 / 5.3 / 5.4 or LuaJIT
===========================================================================
--]]

-- ── Compatibility shims ───────────────────────────────────────────────────
local unpack = table.unpack or unpack
local floor  = math.floor
local function idiv(a, b) return floor(a / b) end

-- ── Configuration ─────────────────────────────────────────────────────────
local CFG = {
  size_mm    = 200,   -- physical output annotation (mm)
  grid_cells = 19,    -- N×N logical cells (odd numbers work best)
  canvas_px  = 760,   -- SVG viewBox dimension
  wall_color  = "#1a1a2e",
  sol_color   = "#e63946",
  start_color = "#2a9d8f",
  end_color   = "#e76f51",
  bg_color    = "#f8f9fa",
}

local N = CFG.grid_cells

-- ── Seeded RNG (xoshiro128-style, pure Lua) ───────────────────────────────
local RNG = {}
RNG.__index = RNG

-- Portable 32-bit helpers (work on Lua 5.1 through 5.4)
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
  -- 32-bit modular multiplication
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
  -- Seed expansion (splitmix32-style)
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

-- ── Thick-grid helpers ────────────────────────────────────────────────────
-- A (2N+1)×(2N+1) boolean grid.
--   Cells (logical i,j) sit at thick-grid position (2i-1, 2j-1).
--   Wall between (i,j)↔(i,j+1) is at (2i-1, 2j).
--   Wall between (i,j)↔(i+1,j) is at (2i,   2j-1).
-- tg[r][c] = true  → passage / open space
-- tg[r][c] = false → wall

local function make_tg()
  local sz = 2*N + 1
  local tg = {}
  for r = 0, sz do
    tg[r] = {}
    for c = 0, sz do tg[r][c] = false end
  end
  return tg, sz
end

local function tg_rc(r, c) return 2*r-1, 2*c-1 end  -- cell → thick-grid

local function open_cell(tg, r, c)
  local tr,tc = tg_rc(r, c); tg[tr][tc] = true
end

local function open_wall(tg, r1, c1, r2, c2)
  tg[r1+r2-1][c1+c2-1] = true
end

-- ── BFS on logical cell grid ──────────────────────────────────────────────
local DIRS4 = {{-1,0},{1,0},{0,-1},{0,1}}

local function cell_bfs(sr, sc, er, ec, passable)
  local function key(r,c) return r*1000+c end
  local parent, vis = {}, {[key(sr,sc)]=true}
  local q, qi = {{sr,sc}}, 1
  while qi <= #q do
    local r,c = q[qi][1], q[qi][2]; qi=qi+1
    if r==er and c==ec then
      local path = {}
      while not(r==sr and c==sc) do
        table.insert(path,1,{r,c})
        local p = parent[key(r,c)]; r,c = p[1],p[2]
      end
      table.insert(path,1,{sr,sc})
      return path
    end
    for _,d in ipairs(DIRS4) do
      local nr,nc = r+d[1], c+d[2]
      local k2 = key(nr,nc)
      if not vis[k2] and passable(nr,nc) then
        vis[k2]=true; parent[k2]={r,c}
        table.insert(q,{nr,nc})
      end
    end
  end
  return nil
end

-- BFS on thick grid (for solution verification)
local function tg_bfs(tg, sz, str, stc, etr, etc)
  local function key(r,c) return r*100000+c end
  local parent, vis = {}, {[key(str,stc)]=true}
  local q, qi = {{str,stc}}, 1
  while qi <= #q do
    local r,c = q[qi][1], q[qi][2]; qi=qi+1
    if r==etr and c==etc then
      local path, walls = {}, {}
      local pr,pc = r,c
      while not(pr==str and pc==stc) do
        table.insert(path,1,{pr,pc})
        local p = parent[key(pr,pc)]
        table.insert(walls,1,{pr+p[1], pc+p[2]})  -- wall midpoint *2 (will halve later)
        pr,pc = p[1],p[2]
      end
      table.insert(path,1,{str,stc})
      -- halve wall coords to get actual thick-grid wall position
      local wn = {}
      for _,w in ipairs(walls) do table.insert(wn,{idiv(w[1],2), idiv(w[2],2)}) end
      return path, wn
    end
    for _,d in ipairs(DIRS4) do
      local wr,wc = r+d[1], c+d[2]
      local nr,nc = r+d[1]*2, c+d[2]*2
      if nr>=0 and nr<=sz and nc>=0 and nc<=sz then
        if tg[nr][nc] and tg[wr][wc] then
          local k2 = key(nr,nc)
          if not vis[k2] then
            vis[k2]=true; parent[k2]={r,c}; table.insert(q,{nr,nc})
          end
        end
      end
    end
  end
  return nil
end

-- ── Solution generator ────────────────────────────────────────────────────
local function generate_solution(rng)
  local sr,sc,er,ec = 1,1,N,N
  local function all_open(r,c) return r>=1 and r<=N and c>=1 and c<=N end
  local opt = cell_bfs(sr,sc,er,ec,all_open)
  local opt_len = #opt - 1
  local target_min = floor(opt_len * 1.52)

  for _=1, 10000 do
    local vis = {}
    local function vk(r,c) return r*1000+c end
    vis[vk(sr,sc)] = true
    local path = {{sr,sc}}
    local at_end = false

    for _=1, N*N*4 do
      local r,c = path[#path][1], path[#path][2]
      if r==er and c==ec then at_end=true; break end
      local long = (#path-1) >= target_min
      local dirs = {{-1,0},{1,0},{0,-1},{0,1}}
      rng:shuffle(dirs)
      local moved = false

      -- Pass 1: prioritised moves
      for _,d in ipairs(dirs) do
        local nr,nc = r+d[1], c+d[2]
        if nr>=1 and nr<=N and nc>=1 and nc<=N and not vis[vk(nr,nc)] then
          if long then
            -- Once long enough, head toward exit
            if nr==er and nc==ec then
              table.insert(path,{nr,nc}); vis[vk(nr,nc)]=true; moved=true; break
            end
            local cd = math.abs(r-er)+math.abs(c-ec)
            local nd = math.abs(nr-er)+math.abs(nc-ec)
            if nd <= cd then
              table.insert(path,{nr,nc}); vis[vk(nr,nc)]=true; moved=true; break
            end
          else
            table.insert(path,{nr,nc}); vis[vk(nr,nc)]=true; moved=true; break
          end
        end
      end
      -- Pass 2: any unvisited neighbour (escape dead-ends)
      if not moved then
        rng:shuffle(dirs)
        for _,d in ipairs(dirs) do
          local nr,nc = r+d[1], c+d[2]
          if nr>=1 and nr<=N and nc>=1 and nc<=N and not vis[vk(nr,nc)] then
            table.insert(path,{nr,nc}); vis[vk(nr,nc)]=true; moved=true; break
          end
        end
      end
      if not moved then break end
    end

    local last = path[#path]
    if at_end or (last[1]==er and last[2]==ec) then
      local sol_len = #path-1
      if sol_len > opt_len * 1.5 then
        return path, opt_len, sol_len
      end
    end
  end

  -- Absolute fallback: boustrophedon snake (always very long)
  local path, vis = {}, {}
  local function vk(r,c) return r*1000+c end
  for r=1,N do
    local cols = {}
    if r%2==1 then for c=1,N do table.insert(cols,c) end
    else            for c=N,1,-1 do table.insert(cols,c) end end
    for _,c in ipairs(cols) do
      if not vis[vk(r,c)] then table.insert(path,{r,c}); vis[vk(r,c)]=true end
    end
  end
  for i=#path,1,-1 do
    if path[i][1]==er and path[i][2]==ec then
      while #path>i do table.remove(path) end; break
    end
  end
  return path, opt_len, #path-1
end

-- ── Maze builder (Wilson's loop-erased random walk) ───────────────────────
local function build_maze(rng, tg, solution)
  -- Carve solution first
  for i,cell in ipairs(solution) do
    open_cell(tg, cell[1], cell[2])
    if i>1 then open_wall(tg, solution[i-1][1], solution[i-1][2], cell[1], cell[2]) end
  end

  -- Wilson's algorithm for remaining cells
  local function is_carved(r,c)
    if r<1 or r>N or c<1 or c>N then return false end
    local tr,tc = tg_rc(r,c); return tg[tr][tc]
  end
  local function vk(r,c) return r*1000+c end

  local uncarved = {}
  for r=1,N do for c=1,N do
    if not is_carved(r,c) then table.insert(uncarved,{r,c}) end
  end end
  rng:shuffle(uncarved)

  for _,start in ipairs(uncarved) do
    if not is_carved(start[1], start[2]) then
      local walk = {start}
      local widx = {[vk(start[1],start[2])]=1}
      local r,c  = start[1], start[2]

      for _=1, N*N*10 do
        if is_carved(r,c) then break end
        local dirs = {{-1,0},{1,0},{0,-1},{0,1}}
        rng:shuffle(dirs)
        local nr,nc
        for _,d in ipairs(dirs) do
          local cr,cc = r+d[1], c+d[2]
          if cr>=1 and cr<=N and cc>=1 and cc<=N then nr=cr; nc=cc; break end
        end
        if not nr then break end

        local k = vk(nr,nc)
        if widx[k] then
          -- Loop erasure
          local li = widx[k]
          for i=li+1,#walk do widx[vk(walk[i][1],walk[i][2])]=nil end
          while #walk>li do table.remove(walk) end
        else
          table.insert(walk,{nr,nc}); widx[k]=#walk
        end
        r,c = nr,nc
      end

      if is_carved(r,c) then
        for i=1,#walk do
          open_cell(tg, walk[i][1], walk[i][2])
          if i>1 then open_wall(tg, walk[i-1][1], walk[i-1][2], walk[i][1], walk[i][2]) end
        end
      end
    end
  end
end

-- ── Verify unique solution & seal shortcuts ───────────────────────────────
local function verify_and_fix(tg, sz, solution)
  local sol_walls = {}
  for i=2,#solution do
    local r1,c1 = solution[i-1][1], solution[i-1][2]
    local r2,c2 = solution[i][1],   solution[i][2]
    sol_walls[(r1+r2-1)*100000+(c1+c2-1)] = true
  end

  local str,stc = tg_rc(solution[1][1],        solution[1][2])
  local etr,etc = tg_rc(solution[#solution][1], solution[#solution][2])

  local function tg_to_cells(tgpath)
    local cells = {}
    for _,nd in ipairs(tgpath) do
      if nd[1]%2==1 and nd[2]%2==1 then
        table.insert(cells, {idiv(nd[1]+1,2), idiv(nd[2]+1,2)})
      end
    end
    return cells
  end

  for _=1, 2000 do
    local tgpath, walls = tg_bfs(tg, sz, str, stc, etr, etc)
    if not tgpath then
      -- Restore solution walls
      for i=2,#solution do
        open_wall(tg, solution[i-1][1], solution[i-1][2], solution[i][1], solution[i][2])
      end
      break
    end
    local found = tg_to_cells(tgpath)
    local ok = (#found == #solution)
    if ok then
      for i=1,#found do
        if found[i][1]~=solution[i][1] or found[i][2]~=solution[i][2] then ok=false; break end
      end
    end
    if ok then break end
    -- Seal one non-solution wall from the alternative path
    local sealed = false
    for _,w in ipairs(walls) do
      local wk = w[1]*100000+w[2]
      if not sol_walls[wk] then tg[w[1]][w[2]]=false; sealed=true; break end
    end
    if not sealed then break end
  end
end

-- ── Entry / exit stubs (open border pixels adjacent to start/end cells) ──
local function open_stubs(tg, sz)
  local etr, etc = tg_rc(N, N)  -- end cell thick-grid position
  tg[0][1]   = true   -- above cell (1,1) start
  tg[etr+1][etc] = true   -- wall below end cell
  tg[etr+2][etc] = true   -- border below end cell (fully exits maze)
end

-- ── SVG renderer ──────────────────────────────────────────────────────────
local function render_svg(tg, sz, solution, show_solution, filepath)
  local px  = CFG.canvas_px
  local cpx = px / (sz + 1)      -- pixels per thick-grid unit
  local off = cpx * 0.5           -- border margin

  local function tx(c) return off + c * cpx end
  local function ty(r) return off + r * cpx end

  local f = io.open(filepath, "w")
  if not f then
    io.stderr:write(string.format("ERROR: cannot write '%s'\n", filepath))
    return false
  end

  local vw = px + off*2
  local vh = px + off*2

  f:write('<?xml version="1.0" encoding="UTF-8"?>\n')
  f:write(string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" '..
    'width="%dmm" height="%dmm" viewBox="0 0 %.2f %.2f">\n',
    CFG.size_mm, CFG.size_mm, vw, vh))

  f:write(string.format(
    '  <rect width="%.2f" height="%.2f" fill="%s"/>\n', vw, vh, CFG.bg_color))

  -- Walls (render 0 to sz-1 to avoid double-thick borders)
  for r=0,sz-1 do
    for c=0,sz-1 do
      if not tg[r][c] then
        f:write(string.format(
          '  <rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s"/>\n',
          tx(c), ty(r), cpx, cpx, CFG.wall_color))
      end
    end
  end

  -- Solution overlay
  if show_solution then
    local lw = cpx * 0.42
    for i=2,#solution do
      local r1,c1 = solution[i-1][1], solution[i-1][2]
      local r2,c2 = solution[i][1],   solution[i][2]
      local tr1,tc1 = tg_rc(r1,c1)
      local tr2,tc2 = tg_rc(r2,c2)
      f:write(string.format(
        '  <line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" '..
        'stroke="%s" stroke-width="%.2f" stroke-linecap="round"/>\n',
        tx(tc1)+cpx/2, ty(tr1)+cpx/2,
        tx(tc2)+cpx/2, ty(tr2)+cpx/2,
        CFG.sol_color, lw))
    end
    -- Entry/exit stub lines
    local str1,stc1 = tg_rc(solution[1][1], solution[1][2])
    local str2,stc2 = tg_rc(solution[#solution][1], solution[#solution][2])
    f:write(string.format(
      '  <line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" '..
      'stroke="%s" stroke-width="%.2f" stroke-linecap="round"/>\n',
      tx(stc1)+cpx/2, ty(str1)+cpx/2, tx(stc1)+cpx/2, ty(str1)-cpx*0.7,
      CFG.sol_color, lw))
    f:write(string.format(
      '  <line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" '..
      'stroke="%s" stroke-width="%.2f" stroke-linecap="round"/>\n',
      tx(stc2)+cpx/2, ty(str2)+cpx/2, tx(stc2)+cpx/2, ty(str2)+cpx*1.5,
      CFG.sol_color, lw))
    -- Start / end circles
    f:write(string.format(
      '  <circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"/>\n',
      tx(stc1)+cpx/2, ty(str1)+cpx/2, lw*0.65, CFG.start_color))
    f:write(string.format(
      '  <circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"/>\n',
      tx(stc2)+cpx/2, ty(str2)+cpx/2, lw*0.65, CFG.end_color))
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
  io.write("  Labyrinth Generator  |  labyrinth.lua    \n")
  io.write(string.format("  200x200 mm  |  %dx%d cell grid         \n", N, N))
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

  io.write(string.format("\n  Seed  : %d\n  Grid  : %dx%d\n", seed_val, N, N))

  local rng    = RNG.new(seed_val)
  local tg, sz = make_tg()

  -- Step 1: Solution
  io.write("[1/5] Generating random-walk solution path... ")
  io.flush()
  local solution, opt_len, sol_len = generate_solution(rng)
  local pct = (sol_len/opt_len - 1) * 100
  io.write("done\n")
  io.write(string.format("      Optimal : %d steps\n", opt_len))
  io.write(string.format("      Solution: %d steps (+%.1f%% longer)\n", sol_len, pct))

  -- Step 2: Stubs
  io.write("[2/5] Opening entry/exit stubs (>=1 cm)...   ")
  io.flush()
  open_stubs(tg, sz)
  io.write("done\n")

  -- Step 3: Maze
  io.write("[3/5] Building maze (Wilson's algorithm)...  ")
  io.flush()
  build_maze(rng, tg, solution)
  io.write("done\n")

  -- Step 4: Verify
  io.write("[4/5] Verifying unique solution path...      ")
  io.flush()
  verify_and_fix(tg, sz, solution)
  io.write("done\n")

  -- Step 5: Output
  io.write("[5/5] Writing output files...\n")

  -- Create mazes directory if it doesn't exist
  local mazes_dir = "mazes"
  os.execute(string.format('if not exist "%s" mkdir "%s" 2>nul || mkdir -p "%s" 2>/dev/null', mazes_dir, mazes_dir, mazes_dir))

  -- Generate filenames based on seed
  local base_name = string.format("maze_%04d_square", seed_val)
  local maze_file = string.format("%s/%s.svg", mazes_dir, base_name)
  local solution_file = string.format("%s/%s_solution.svg", mazes_dir, base_name)
  local params_file = string.format("%s/%s.json", mazes_dir, base_name)

  local ok1 = render_svg(tg, sz, solution, false, maze_file)
  if ok1 then io.write(string.format("      %s written\n", maze_file)) end

  local ok2 = render_svg(tg, sz, solution, true, solution_file)
  if ok2 then io.write(string.format("      %s written\n", solution_file)) end

  local sol_list = {}
  for _,cell in ipairs(solution) do
    table.insert(sol_list, {row=cell[1], col=cell[2]})
  end

  local ok3 = write_json(params_file, {
    generator             = "labyrinth.lua",
    version               = "1.0.0",
    seed                  = seed_val,
    physical_size_mm      = CFG.size_mm,
    grid_cells_per_side   = N,
    svg_canvas_px         = CFG.canvas_px,
    start_cell            = {row=1, col=1},
    end_cell              = {row=N, col=N},
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

  io.write(string.format("\nDone! All output files written to %s/\n", mazes_dir))
end

main()
