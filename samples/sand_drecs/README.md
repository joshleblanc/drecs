# sand_drecs — falling-sand sim in drecs

A falling-sand simulation built on drecs ECS. Each grain of sand, water, or
wall is a separate entity with components `Position`, `Color`, and a material
tag (`Sand`/`Water`/`Wall`). Spawn with mouse, paint different materials,
erase with right-click, clear with `C`.

## Run it

```
dragonruby.exe drecs --sample sand_drecs
```

The drecs_parallel C extension is auto-loaded on first tick — when it is,
both the sim and render loops go through the fast `Drecs::Parallel.each_row`
path. When the extension can't be loaded (missing DLL, test environments),
the per-row loop falls back to pure Ruby automatically — same code, slower.

## Sizing

Sized to fill the 1280×720 720p window: `GRID_W=80, GRID_H=45, CELL_PX=16`,
so each cell is a 16×16 pixel square. 3,600 cells total — well within sim
budget. A thin HUD bar overlays the top 36px so the grid gets the full 720px.

Going smaller (CELL_PX=8 → 160×90 = 14,400 cells) tanks the C each_row path
at high grain counts because the per-row block still runs in Ruby. If you
need a finer grid, write a native system that walks the drecs struct stores
and pushes to `args.outputs` directly.

## What this sample demonstrates

### 1. Per-material archetypes instead of one `kind` field

Sand, water, and wall are THREE separate component classes (`Drecs.tag(:sand)`,
etc.), so they live in three SEPARATE archetypes:

```ruby
world.each_entity(Position, Sand, Color) { |id, pos, _tag, color| ... }
world.each_entity(Position, Water, Color) { |id, pos, _tag, color| ... }
# walls never appear in either loop — they're not iterated at all
```

This is faster than one archetype with a `kind: :sand` enum because:
- The inner block doesn't have to `next unless kind.value == :sand`
- Walls cost zero per tick in the sim (they're not in any sim loop)
- The C-backed `each_row` doesn't have to skip non-matching rows in Ruby

### 2. Direct ivar mutation on Position

Position is an ivar-backed class (`Drecs.component(:x, :y)`). When sand
falls, we mutate `pos.x = nx; pos.y = ny` directly — drecs sees the change
because the world's component store holds the same struct reference.

This makes the move a 2-write operation; no `world.set_component` /
`world.add_component` / archetype migration needed.

### 3. Spatial index as a plain Ruby Array

Drecs doesn't ship a spatial grid (entities have integer IDs, components
live in SoA stores — there's no "cell X is occupied?" primitive). We
maintain a side-array `@grid = Array.new(GRID_W * GRID_H, 0)` that maps
`(x, y)` → entity_id (or 0). It's used for:
- O(1) "is cell empty?" checks in `simulate_sand` / `simulate_water`
- O(1) "destroy the entity at this cell" in the erase brush

### 4. Auto-loaded C extension

The first thing `tick` does is `load_parallel_extension`, which calls
`DR.dlopen 'drecs_parallel'; Drecs::Parallel.load`. After that, every
`world.each_entity` call delegates the per-row loop body to
`Drecs::Parallel.each_row` — a C function that specializes the
0/1/2/3/4-store case and dispatches via `mrb_yield_argv`. Bench at 40k
entities shows ~6-7x speedup over the pure-Ruby `while/case/yield`
loop. See `samples/each_row_bench` for the benchmark.

## Controls

| Action                 | Input                                 |
|------------------------|---------------------------------------|
| Paint                  | Hold left mouse button                |
| Erase                  | Hold right mouse button               |
| Material: sand         | `1`                                   |
| Material: water        | `2`                                   |
| Material: wall         | `3`                                   |
| Shrink brush           | `[`                                   |
| Grow brush             | `]`                                   |
| Pause simulation       | `Space`                               |
| Clear all              | `C`                                   |

## Performance notes

- **Sim cost** is `O(n)` per tick where `n` is the active grain count,
  with a small constant per row. Sand and water iterate only their own
  archetype, walls are skipped entirely.
- **Render cost is zero per frame.** Each grain has a pre-allocated
  `SandGrain`/`WaterGrain`/`WallGrain` instance (`attr_sprite` class,
  `@path = :solid`) that we push into `args.outputs.static_sprites`
  ONCE on spawn and remove on destroy. The sim loop mutates
  `grain.x = ...` / `grain.y = ...` as grains move; DR's sprite
  pipeline reads the iVars directly. No per-frame hash allocation,
  so 5000+ grains are no harder on GC than 50. **This is the key
  optimization — without it, `args.outputs.solids << { ... }`
  allocates a Hash per primitive per frame, ~150k allocations/sec
  at 2500 grains @ 60fps, which OOMs the GC and crashes the sample
  around the 2500-grain mark.**
- **C extension** is required for the per-row loop speedup. The
  bench at `samples/each_row_bench` measures the speedup. The whole
  `each_entity` API has the same fallback path either way — no
  code change needed when the extension isn't loaded.

## Three gotchas worth knowing

1. **DR's y-axis is bottom-up.** `y=0` is the bottom of the screen,
   `y=H-1` is the top. So "falling down" means DECREASING `y`. The
   sim rules try `(x, y-1)` first, then `(x±1, y-1)` for diagonal.

2. **Don't `world.destroy` inside an `each_entity` block.** Drecs's
   `destroy` uses swap-and-pop on the archetype's `entity_ids` array,
   so the array shrinks mid-iteration. The C-backed `each_row` reads
   past the new end and crashes; the Ruby fallback path visits
   swapped-in entities twice and skips others. Collect ids first,
   THEN destroy:

   ```ruby
   # WRONG — crashes with the C extension:
   world.each_entity(Position) { |id, _p| world.destroy(id) }

   # RIGHT:
   ids = []
   world.each_entity(Position) { |id, _p| ids << id }
   ids.each { |id| world.destroy(id) }
   ```

   The same rule applies to `world.add_component` (which can also
   mutate the archetype's entity_ids array during archetype migration).

3. **`args.outputs.solids << { ... }` per frame OOMs at high counts.**
   This was the cause of the "crashes around 2500 sand" bug. Each
   Hash allocation is GC-tracked; at 60fps × 2500 grains that's
   150k allocations/sec, which the GC can't reclaim fast enough and
   eventually raises. The fix is `args.outputs.static_sprites` with
   pre-allocated renderable instances. Once you do that, the render
   loop has no per-frame allocation and 5000+ grains is no harder on
   the GC than 50. The first version of this sample used `solids`
   and crashed around 2500 grains; switching to `static_sprites`
   + `attr_sprite` raised the ceiling to 5000+ with 60fps held.

## Files

- `app/main.rb` — the entire sample (~390 lines).
- `errors/readme.txt` — drecs writes `last.txt` here if the sample
  crashes (drecs's standard error convention).
