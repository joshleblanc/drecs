# sand_drecs sample — falling-sand simulation in drecs ECS.
#
# Run with:
#   dragonruby.exe drecs --sample sand_drecs
#
# Each grain of sand / water / wall is a drecs entity with components
# (Position, Color, plus a material tag class). Materials live in
# SEPARATE archetypes — sand, water, wall each get their own
# (Position, Color, MaterialTag) archetype — so the simulation can
# query `world.each_entity(Position, Sand, Color)` and skip walls
# entirely without per-row filtering.
#
# Why per-material archetypes instead of one archetype with a
# `kind: :sand` enum:
#   1. The sim rule differs per material (sand tries 3 cells, water
#      tries 5, wall is static). With separate archetypes, each
#      `each_entity` query only sees the entities it can act on —
#      no `next if kind.value == :sand` checks in the inner loop.
#   2. The C-backed `Drecs::Parallel.each_row` path is at its best
#      when the per-row block is the only Ruby work in the loop.
#      Filtering out non-matching rows in Ruby would defeat it.
#
# The hot paths:
#   - Sim tick: 3 separate `each_entity` calls, one per material.
#   - Render:   one `each_entity(Position, Color)` that yields every
#     grain (or two: one for walls as background, one for sand/water
#     as foreground — see render()).
#
# Both run through Drecs::Parallel.each_row when the C extension is
# loaded, falling back to a pure-Ruby while/case loop otherwise.
#
# The spatial index `@grid` is plain Ruby — drecs doesn't ship a
# grid, so we maintain one for O(1) "is cell (x,y) empty?" lookups.
# A grain's entity_id is stored in @grid[gy * GRID_W + gx] so the
# erase brush can find the entity to destroy.
#
# Controls:
#   Left click + drag   spawn current material under cursor (3-cell brush)
#   Right click + drag  erase grains under cursor
#   1 / 2 / 3           switch material: sand / water / wall
#   [ / ]               shrink / grow brush radius (1-6)
#   C                   clear all grains
#   Space               pause simulation (rendering still updates)

# Sized to fill the 1280x720 720p window. CELL_PX = 16 keeps the
# cell count (80 * 45 = 3600 max) within sim budget; smaller cells
# (CELL_PX = 8 → 160*90 = 14400) tank the C each_row path at high
# grain counts because the per-row block runs in Ruby.
GRID_W     = 80 *4 
GRID_H     = 45 * 4
CELL_PX    = 4
VIEWPORT_W = GRID_W * CELL_PX    # 1280
VIEWPORT_H = GRID_H * CELL_PX    # 720

HUD_H = 36   # thin overlay bar at the top, doesn't reduce grid area

$DEBUG_SPAWN = false
$DEBUG_BRUSH = false

# ---- Components ---------------------------------------------------------

# Position is the cell coord. Color is per-grain (sand has slight hue
# variation in some builds; here we keep one color per material for
# simplicity, but the Color component lets us vary per-grain later
# without changing the archetype signature).
Position = Drecs.component(:x, :y)
Color    = Drecs.component(:r, :g, :b)

# Material tags. Drecs.tag(name) returns a zero-field marker class
# (introspectable via `Sand.tag_name`); instances carry no payload but
# the class is distinct so drecs sees three different archetype
# signatures:
#   (Position, Color, Sand)
#   (Position, Color, Water)
#   (Position, Color, Wall)
Sand  = Drecs.tag(:sand)
Water = Drecs.tag(:water)
Wall  = Drecs.tag(:wall)

MATERIAL_INFO = {
  sand:  { tag: Sand,  color: [220, 195, 140] },
  water: { tag: Water, color: [ 60, 110, 170] },
  wall:  { tag: Wall,  color: [130, 130, 130] },
}

# ---- Renderables --------------------------------------------------------

# Persistent renderable per grain. We push ONE instance into
# `args.outputs.static_sprites` per entity and mutate its @x/@y/@r/@g/@b
# each tick. No per-frame hash allocation; the sprite pipeline reads
# the iVars directly. This is what makes 5k+ grains viable — without
# it, `args.outputs.solids << { x:, y:, ... }` allocates a Hash per
# primitive per frame, ~150k allocations/sec at 2500 grains @ 60fps,
# which OOMs the GC.
#
# Each grain type is its own class (not a shared base) so DR's sprite
# pipeline can use the class to look up the cached sprite primitive.
class SandGrain
  attr_sprite
  def initialize
    @path = :solid
    @w    = CELL_PX
    @h    = CELL_PX
    @r    = 220
    @g    = 195
    @b    = 140
    @a    = 255
    @x    = 0
    @y    = 0
  end
end

class WaterGrain
  attr_sprite
  def initialize
    @path = :solid
    @w    = CELL_PX
    @h    = CELL_PX
    @r    = 60
    @g    = 110
    @b    = 170
    @a    = 255
    @x    = 0
    @y    = 0
  end
end

class WallGrain
  attr_sprite
  def initialize
    @path = :solid
    @w    = CELL_PX
    @h    = CELL_PX
    @r    = 130
    @g    = 130
    @b    = 130
    @a    = 255
    @x    = 0
    @y    = 0
  end
end

GRAIN_CLASS = {
  sand:  SandGrain,
  water: WaterGrain,
  wall:  WallGrain,
}

# ---- Logging ------------------------------------------------------------

LOG_PATH = 'sand_drecs_log.txt'

def flog(msg)
  $stdout.puts msg rescue nil
  begin
    File.open(LOG_PATH, 'a') { |f| f.puts msg }
  rescue
  end
end

# Auto-load the drecs_parallel C extension so we get the fast
# each_row path. Safe to call multiple times.
def load_parallel_extension
  return if @parallel_loaded
  @parallel_loaded = true
  begin
    DR.dlopen 'drecs_parallel'
    Drecs::Parallel.load
    flog "[sand_drecs] drecs_parallel loaded, each_row=#{Drecs::Parallel.respond_to?(:each_row)}"
  rescue => e
    flog "[sand_drecs] drecs_parallel load failed: #{e.message} — using pure-Ruby each_entity"
  end
end

# ---- Spatial index ------------------------------------------------------

# @grid maps cell -> entity_id (0 = empty).
# Maintained on spawn/move/destroy. The simulation reads it to answer
# "can I fall into cell (nx, ny)?" without scanning all entities.
def empty?(grid, nx, ny)
  return false if nx < 0 || nx >= GRID_W || ny < 0 || ny >= GRID_H
  grid[grid_index(nx, ny)] == 0
end

def grid_index(x, y)
  y * GRID_W + x
end

# ---- Spawn / move / destroy ---------------------------------------------

def spawn_grain(world, grid, renderables, static_sprites, gx, gy, kind)
  # Coerce to integer — coordinates must be grid cells, never floats.
  gx = gx.to_i
  gy = gy.to_i
  return nil if gx < 0 || gx >= GRID_W || gy < 0 || gy >= GRID_H
  idx = grid_index(gx, gy)
  return nil unless grid[idx] == 0
  info = MATERIAL_INFO[kind]
  e = world.spawn(
    Position.new(gx, gy),
    info[:tag].new,
    Color.new(*info[:color])
  )
  grid[idx] = e

  # Allocate a persistent renderable and push it to static_sprites.
  # The render loop mutates renderable.x / .y directly — DR's sprite
  # pipeline reads the iVars each frame, so there is no per-frame
  # allocation. We track renderables keyed by entity_id (NOT by row)
  # because drecs's swap-and-pop on destroy changes row order.
  grain = GRAIN_CLASS[kind].new
  grain.x = gx * CELL_PX
  grain.y = gy * CELL_PX
  renderables[e] = grain
  static_sprites << grain
  e
end

# Mutates pos directly (Position is ivar-backed; drecs sees the
# mutation immediately). Updates @grid so neighbors see the new
# occupancy. Also pushes the new screen-pixel coords into the
# renderable so DR's sprite pipeline picks them up next frame.
def move_grain(grid, renderables, pos, nx, ny)
  return false if nx < 0 || nx >= GRID_W || ny < 0 || ny >= GRID_H
  old_idx = grid_index(pos.x, pos.y)
  new_idx = grid_index(nx, ny)
  return false if grid[new_idx] != 0
  e = grid[old_idx]
  grid[old_idx] = 0
  grid[new_idx] = e
  pos.x = nx
  pos.y = ny
  # Push the new screen coords to the renderable. We need to know
  # WHICH entity is moving to look up its renderable — but the grid
  # stored the entity_id, and we use that as the renderables key.
  if (grain = renderables[e])
    grain.x = nx * CELL_PX
    grain.y = ny * CELL_PX
  end
  true
end

# Destroy a grain at the given cell. Resets the grid slot and
# removes the matching renderable from static_sprites.
def destroy_grain(world, grid, renderables, static_sprites, gx, gy)
  return if gx < 0 || gx >= GRID_W || gy < 0 || gy >= GRID_H
  idx = grid_index(gx, gy)
  e = grid[idx]
  return if e.nil? || e == 0
  grid[idx] = 0
  if (grain = renderables.delete(e))
    # Remove from static_sprites — array `delete` is O(n) but erase
    # brushes only fire when the user holds RMB, not every tick.
    static_sprites.delete(grain)
  end
  world.destroy(e)
end

# ---- Simulation ---------------------------------------------------------

# Sand rule: try straight down, then down-left, then down-right.
# Wall rule: never moves.
def simulate_sand(world, grid, renderables)
  # Sand falls DOWN on screen. DR's y-axis is bottom-up (y=0 is the
  # bottom of the screen, y=GRID_H-1 is the top), so "down" means
  # DECREASING y. We try (x, y-1), then (x-1, y-1), then (x+1, y-1).
  world.each_entity(Position, Sand, Color) do |id, pos, _tag, _color|
    gx = pos.x
    gy = pos.y
    if empty?(grid, gx, gy - 1)
      move_grain(grid, renderables, pos, gx, gy - 1)
    elsif empty?(grid, gx - 1, gy - 1)
      move_grain(grid, renderables, pos, gx - 1, gy - 1)
    elsif empty?(grid, gx + 1, gy - 1)
      move_grain(grid, renderables, pos, gx + 1, gy - 1)
    end
  end
end

# Water rule: try down, down-left, down-right, left, right.
# Water is also displaceable — if sand falls onto it, the sand and
# water should swap. We approximate that by letting sand fall into
# a water cell, then re-tagging the cell to water. To keep this
# sample simple we DON'T implement that swap; sand sits on top of
# water if you put water underneath sand. (DR's built-in sand sim
# does swap; see samples/99_genre_simulation/sand_simulation.)
def simulate_water(world, grid, renderables)
  # Water falls DOWN (gy-1) and spreads sideways when blocked.
  world.each_entity(Position, Water, Color) do |id, pos, _tag, _color|
    gx = pos.x
    gy = pos.y
    if empty?(grid, gx, gy - 1)
      move_grain(grid, renderables, pos, gx, gy - 1)
    elsif empty?(grid, gx - 1, gy - 1)
      move_grain(grid, renderables, pos, gx - 1, gy - 1)
    elsif empty?(grid, gx + 1, gy - 1)
      move_grain(grid, renderables, pos, gx + 1, gy - 1)
    elsif empty?(grid, gx - 1, gy)
      move_grain(grid, renderables, pos, gx - 1, gy)
    elsif empty?(grid, gx + 1, gy)
      move_grain(grid, renderables, pos, gx + 1, gy)
    end
  end
end

# Walls are stationary. The render loop still iterates them, but the
# simulation does not. This is exactly the value of per-material
# archetypes: walls cost nothing per tick.

# ---- Input --------------------------------------------------------------

def handle_input(args, world, grid, renderables, static_sprites)
  if args.inputs.keyboard.key_down.c
    clear_grid(world, grid, renderables, args.outputs.static_sprites)
    args.state.flash = 'cleared'
    return
  end

  if args.inputs.keyboard.key_down.space
    args.state[:paused] = !args.state[:paused]
  end

  # Material switch: 1 = sand, 2 = water, 3 = wall.
  if args.inputs.keyboard.key_down.one
    args.state[:current_material] = :sand
  elsif args.inputs.keyboard.key_down.two
    args.state[:current_material] = :water
  elsif args.inputs.keyboard.key_down.three
    args.state[:current_material] = :wall
  end

  # Brush radius: [ shrinks, ] grows.
  if args.inputs.keyboard.key_down.open_square_brace
    args.state[:brush_radius] = [args.state[:brush_radius] - 1, 1].max
  end
  if args.inputs.keyboard.key_down.close_square_brace
    args.state[:brush_radius] = [args.state[:brush_radius] + 1, 6].min
  end

  # Mouse → cell
  mx = args.inputs.mouse.x
  my = args.inputs.mouse.y
  return unless mx && my && my >= 0
  gx = (mx / CELL_PX).to_i
  gy = (my / CELL_PX).to_i
  return if gx < 0 || gx >= GRID_W || gy < 0 || gy >= GRID_H

  radius = args.state[:brush_radius]
  r2 = radius * radius

  # `args.inputs.mouse.button_left` / `.button_right` are booleans
  # that are TRUE on EVERY tick the corresponding mouse button is
  # held. Use these for "paint while dragging" behavior.
  #
  # NOTE: don't confuse with `mouse.down` / `mouse.up` — those return
  # a click/release Entity (or nil) and are TRANSIENT (truthy only on
  # the press/release tick). `mouse.down > 0` would also crash because
  # the click Entity doesn't have a `>` method.
  left_held  = args.inputs.mouse.button_left
  right_held = args.inputs.mouse.button_right

  if left_held
    kind = args.state[:current_material]
    (-radius..radius).each do |dy|
      (-radius..radius).each do |dx|
        next if dx * dx + dy * dy > r2
        spawn_grain(world, grid, renderables, static_sprites, gx + dx, gy + dy, kind)
      end
    end
  elsif right_held
    (-radius..radius).each do |dy|
      (-radius..radius).each do |dx|
        next if dx * dx + dy * dy > r2
        destroy_grain(world, grid, renderables, static_sprites, gx + dx, gy + dy)
      end
    end
  end
end

def clear_grid(world, grid, renderables, static_sprites)
  # CRITICAL: collect ids first, THEN destroy. Destroying during
  # iteration crashes because drecs's `destroy` uses swap-and-pop
  # on the archetype's entity_ids array — the array shrinks mid-
  # iteration and the C-backed `each_row` reads past the new end.
  ids = []
  world.each_entity(Position) { |id, _pos| ids << id }
  ids.each do |id|
    if (grain = renderables.delete(id))
      static_sprites.delete(grain)
    end
    world.destroy(id)
  end
  grid.length.times { |i| grid[i] = 0 }
end

# ---- Render -------------------------------------------------------------

# We render walls + grains as filled rectangles. To avoid the
# per-frame hash allocation tax at high grain counts, we push
# args.outputs.solids << { ... } which DOES allocate. For ~3000
# grains at 60fps that's 180k allocations/sec — borderline. The
# each_entity C path handles the iteration; allocation is in the
# block (hash literal). If this becomes the bottleneck, the right
# fix is to push to args.outputs.static_sprites with pre-allocated
# grain instances keyed by entity_id (see dragonruby-drecs memory
# topic, "Pre-allocated renderable pool" section). That's a
# separate optimization; not done here so the sample stays small.
def render(args, world)
  # Background — one rect, allocates once per frame.
  args.outputs.solids << { x: 0, y: 0, w: VIEWPORT_W, h: VIEWPORT_H, r: 18, g: 22, b: 30 }

  # Grains render through args.outputs.static_sprites — pre-allocated
  # SandGrain/WaterGrain/WallGrain instances whose @x/@y we mutated in
  # spawn_grain / move_grain / destroy_grain. NO per-frame allocation
  # per grain (this is the difference between 60fps at 5000 grains
  # and OOM at 2500 grains).

  render_hud(args, world)
end

def render_hud(args, world)
  # Thin overlay bar at the TOP so the grid gets the full 720px.
  grain_count = world.entity_count
  paused = args.state[:paused] ? '  [PAUSED]' : ''
  mat = args.state[:current_material]
  radius = args.state[:brush_radius]

  # Translucent top bar.
  args.outputs.solids << { x: 0, y: VIEWPORT_H - HUD_H, w: VIEWPORT_W, h: HUD_H, r: 0, g: 0, b: 0, a: 180 }

  args.outputs.labels << {
    x: 8, y: VIEWPORT_H - 8,
    text: "material: #{mat}   brush: #{radius}   grains: #{grain_count}#{paused}",
    r: 220, g: 220, b: 220
  }
  args.outputs.labels << {
    x: 8, y: VIEWPORT_H - 26,
    text: "LMB: paint   RMB: erase   1/2/3: sand/water/wall   [/]: brush   Space: pause   C: clear",
    r: 140, g: 140, b: 140, size_enum: -2
  }
end

# ---- Tick ---------------------------------------------------------------

def tick(args)
  begin
    load_parallel_extension

    # Use symbol keys (matching nbody_gravity / native_boids pattern)
    # so values reliably persist across ticks.
    args.state[:world]            ||= Drecs::World.new
    args.state[:grid]             ||= Array.new(GRID_W * GRID_H, 0)
    args.state[:renderables]      ||= {}
    args.state[:current_material] ||= :sand
    args.state[:brush_radius]     ||= 3
    args.state[:paused]           ||= false

    world       = args.state[:world]
    grid        = args.state[:grid]
    renderables = args.state[:renderables]

    unless args.state[:boot_spawned]
      args.state[:boot_spawned] = true
      # Three bands across the top: sand, water, wall, sand again —
      # ~960 grains. Uses ~32% of the grid; rest is empty for the
      # player to paint into.
      3.times do |row|
        GRID_W.times do |col|
          kind = (col / (GRID_W / 4)) % 3 == 0 ? :sand : (col / (GRID_W / 4)) % 3 == 1 ? :water : :wall
          spawn_grain(world, grid, renderables, args.outputs.static_sprites,
                      col, GRID_H - 1 - row, kind)
        end
      end
      flog "[sand_drecs] boot: spawned ~#{world.entity_count} grains"
    end

    handle_input(args, world, grid, renderables, args.outputs.static_sprites)

    unless args.state[:paused]
      simulate_sand(world, grid, renderables)
      simulate_water(world, grid, renderables)
    end

    render(args, world)

    if (args.state.tick_count % 60).zero?
      flog "[sand_drecs] t=#{args.state.tick_count} grains=#{world.entity_count} fps=#{DR.current_framerate.round(1)}"
    end
  rescue Exception => e
    # If the sample crashes, dump a backtrace + state to the log so
    # we can diagnose without needing the OS crash dialog.
    flog "[sand_drecs] CRASH at t=#{args.state.tick_count}: #{e.class}: #{e.message}"
    flog "[sand_drecs] BACKTRACE: #{e.backtrace.first(20).join("\n")}"
    flog "[sand_drecs] STATE: grains=#{args.state[:world].entity_count} renderables=#{args.state[:renderables].size}"
    raise
  end
end
