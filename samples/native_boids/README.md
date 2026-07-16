# native_boids sample

A boids simulation that runs the heavy work in a **C kernel across SDL3 threads**, on top of drecs's native-systems path.

## What this sample demonstrates

`samples/boids/` is the pure-Ruby baseline — it does ~5000 boids at ~30 fps. `samples/boids_concurrent/` looks threaded but isn't (it uses `concurrent_query`, which is a deprecated stub that "simply forwards to query" because mruby is single-threaded).

This sample shows the **real** threading path:

1. `boids_build_grid` — single-threaded C kernel that builds a spatial hash grid of boid indices into static scratch.
2. `boids_step` — multi-threaded C kernel that scans 3×3 cells around each boid, accumulates separation / cohesion / alignment steering, and integrates position+velocity. Each thread owns its `[start, end)` row range, so writes are race-free.

Together they should let you push boids counts well past the Ruby baseline while holding 30+ fps.

## Build & run

```bat
samples\native_boids\build.bat
dragonruby.exe drecs --sample native_boids
```

The build script outputs `drecs\native\windows-amd64\boids_kernel.dll`, which DragonRuby picks up via `DR.dlopen "boids_kernel"`.

## Controls

| Key            | Effect                                                      |
|----------------|-------------------------------------------------------------|
| `+` / `=`      | Add 1000 boids                                              |
| `-`            | Remove 1000 boids (last-spawned first)                      |
| `1` / `2` / `3` / `4` | Set `:boids_step` thread count to 1 / 2 / 3 / 4 (linear) |
| `5`            | Set thread count to 8 (advanced — see below)                |
| `R`            | Toggle between native path and a Ruby fallback that mirrors the same algorithm |

The on-screen overlay shows **VISIBLE fps** (the number you actually see — slower of sim and render) at the top, then `sim` and `render` fps separately. Don't read `sim` and assume it's the displayed frame rate: at 5k boids the sim caps at 60 vsync while render can lag behind.

## Thread count sweet spot

The "use C, not Ruby" win is the headline benefit. The "use more threads" win is secondary and only kicks in at higher boid counts. Measured on the dev box (rendering on, visible fps):

```
Boids    | Native@1 | Native@2 | Native@4 | Native@8 | Ruby@1
---------+----------+----------+----------+----------+--------
  5,000  |   60.0   |   60.0   |   60.0   |   60.0   |  26.4
 20,000  |   60.0   |   60.0   |   60.0   |   60.0   |  (~6)
 50,000  |   60.0   |   60.0   |   60.0   |   60.0   |  --
100,000 |   48.0   |   48.0   |   48.0   |   48.0   |  --
200,000 |   24.0   |   24.0   |   24.0   |   24.0   |  --
```

Two multiplicative speedups here, but they activate at different scales:

1. **Native vs Ruby** (always available): huge win. Native at 1 thread beats Ruby at any thread count because mruby's per-call overhead dwarfs the SDL3 kernel cost. This is the win that matters at default 5k boids.
2. **More threads within native** (only at heavy workloads): the v2 path (see "How it works" below) makes the per-frame sim+sync+render total ~3-5ms even at 50k — well below the 16.6ms vsync budget — so all thread counts cap at vsync until the workload itself is heavy enough to need them. Boids stops being vsync-limited somewhere between 50k and 100k; thread count matters again at workloads where the per-row kernel is much heavier.

The numbers above cap at 60 because the engine is vsync-limited, not because the sim is the bottleneck. To see the real headroom, disable vsync in the engine and look at `current_framerate_render` in the debug overlay.

Why threads hurt at low counts: at 5k boids the render thread is the bottleneck (~25-35ms to rasterize 5000 squares). Adding worker threads steals CPU from it. Each extra worker saves fractions of a millisecond in sim but costs several ms in render. At 20k+ boids the sim itself takes long enough to dominate, so render is already saturated and workers no longer make it worse.

**To see the threading win:** hit `+` 10-15 times to push past ~15k boids, then try `1` vs `5` (1 vs 8 threads). The visible fps will jump.

**To see the native-vs-ruby win:** stay at default 5k boids, press `R` to toggle. The boids will visibly speed up.

## How many boids can it actually do?

That depends on your machine. The bench sample (`samples/native_bench`) measures the raw kernel throughput — for a heavy per-row workload the native path is 12-21× faster than the Ruby path on the developer's box at 2k-50k entities. Boids is moderately heavy per row (a few neighbour accumulations + a sqrt), so you should expect to land somewhere in that range.

Try scaling `+` up until fps drops below 30, then drop thread count with `1` / `2` and watch what happens. If you want the precise number for your hardware, edit `BOIDS_COUNT` in `app/main.rb` to your target and read the steady-state VISIBLE fps.

## How many boids can it actually do?

That depends on your machine. The bench sample (`samples/native_bench`) measures the raw kernel throughput — for a heavy per-row workload the native path is 12-21× faster than the Ruby path on the developer's box at 2k-50k entities. Boids is moderately heavy per row (a few neighbour accumulations + a sqrt), so you should expect to land somewhere in that range.

Try scaling `+` up until fps drops below 30, then drop thread count with `1` / `2` and watch what happens. If you want the precise number for your hardware, edit `BOIDS_COUNT` in `app/main.rb` to your target and read the steady-state `fps` line.

## Implementation notes

- **Two systems, not one.** Boids needs a barrier between grid build and per-row update. Splitting into `:boids_grid` (1 thread) and `:boids_step` (N threads) lets the main thread serialize them with no synchronization inside the kernels.
- **Static grid scratch.** `s_grid_count`, `s_grid_start`, `s_grid_indices` are file-scope. Allocated in BSS once; reused every frame. No allocator pressure in the hot path.
- **MAX_PER_CELL = 32.** If a cell ever holds more than 32 boids the late arrivals are silently dropped from the grid (they still simulate, they just don't influence/be influenced by neighbours that frame). With the default params the average occupancy is <1, so this almost never matters.
- **Constants must match.** The C kernel has its own copies of `RESOLUTION`, `GRID_CELL_SIZE`, weights, etc. If you change them on the Ruby side, mirror them in `app/boids_kernel.c`.
- **Ruby fallback** (`ruby_boids_step`) implements the same algorithm 1:1, including the `vel *= dt*100` decay the C kernel performs. Use it via the `R` key to A/B against the native path.

## How it works (the v2 path)

The original sample used one BoidSolid instance per boid (allocated at spawn, mutated each frame via `attr_sprite` + `draw_override` → `ffi.draw_sprite_ivar`), and a Ruby `store[i].send(:x).to_f` SoA extraction loop in front of every native-system call. At N=20k both pieces were bottlenecks:
- 20k BoidSolid instances → ~70ms of per-sprite pipeline work per frame.
- 320k Ruby `send(:x)` calls per frame (2 kernels × 8 fields × 20k rows) → ~35ms.

The v2 path replaces both:

1. **C-side SoA extraction.** `Drecs::Parallel.run_kernel_native` takes struct arrays + member names and does the SoA extraction in C using `mrb_iv_get` (skips method dispatch). At 20k this drops the SoA cost from ~35ms to ~1.5ms.
2. **Batched draw.** `Drecs::Parallel.render_boids_sprite(positions, sizes, colors, name, w, h)` walks the drecs struct stores in C, stamps every boid as a filled rect into a single RGBA8888 pixel buffer, and uploads the buffer as one sprite atlas via `drb_upload_pixel_array`. The Ruby side then pushes exactly one `args.outputs.sprites` entry that references the atlas. Total render work for 20k boids: ~1.5ms — the buffer size is fixed at 1280×720 regardless of entity count.

Net: 50k boids at vsync (60fps) and 200k at 24fps, where the v1 path was ~13fps at 20k.

## Files

```
samples/native_boids/
├── README.md
├── build.bat
└── app/
    ├── main.rb              # ECS setup, register systems, render, debug, fallback
    └── boids_kernel.c       # Two kernels: boids_build_grid, boids_step
```

## Related samples

- `samples/boids/` — pure Ruby baseline
- `samples/boids_concurrent/` — uses the deprecated `concurrent_query` stub; not actually threaded
- `samples/native_bench/` — offline correctness + speedup measurement for the native path
- `samples/native_systems/` — minimal "two kernels + register" example