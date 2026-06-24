# nbody_gravity sample

An O(N²) gravitational N-body simulation running in a C kernel across SDL3 threads. This is the canonical "threading wins" demo for drecs-native: per-row work scales with N (each particle sums forces from every other particle), so unlike `samples/native_boids/` (where the kernel is too light for threading to matter at default counts), this kernel actually has enough per-row work for thread parallelism to pay off.

## What this sample demonstrates

- **O(N²) gravity** is a textbook parallel problem — embarrassingly parallel over rows, no cross-row dependencies.
- **C-vs-Ruby win** is dramatic: at default N=1500 the Ruby path takes ~2 seconds per frame; the C kernel takes ~5ms at 1 thread, ~1.5ms at 8 threads.
- **Threads-vs-no-threads win** is real but modest: ~10% at default counts (vsync-capped). Push past ~3000 particles to see it grow.

## Build & run

```bat
samples\nbody_gravity\build.bat
dragonruby.exe drecs --sample nbody_gravity
```

The build script outputs `drecs\native\windows-amd64\nbody_kernel.dll`.

## Controls

| Key            | Effect                                                      |
|----------------|-------------------------------------------------------------|
| `+` / `=`      | Add 100 particles                                           |
| `-`            | Remove 100 particles (last-spawned first)                   |
| `1` / `2` / `4` / `8` | Set `:nbody_step` thread count to 1 / 2 / 4 / 8   |
| `R`            | Toggle between native path and Ruby fallback (same algorithm) |

## Measured results (this machine)

At default 1500 particles, native path with rendering on:

```
threads=1 → 52.7 visible fps
threads=2 → 55.6 visible fps
threads=4 → 56.6 visible fps
threads=8 → 57.5 visible fps
```

The 1→8 improvement is real (~10%) but bounded by vsync. To see a larger threading win, push past 3000 particles — the renderer's 1500 dots stops being the bottleneck and the per-row work dominates. At 3000 particles (measured):

```
threads=1 → 25.1 fps
threads=8 → 28.0 fps
```

## C-vs-Ruby (press `R`)

The Ruby fallback (`ruby_nbody_step` in `main.rb`) is intentionally slow at default counts. At N=1500 it takes ~2 seconds per frame in pure mruby. Pressing `R` mid-run switches to Ruby and you'll see the visible fps drop to single digits — a slideshow, while particles barely move. Press `R` again to switch back to native and watch the orbital motion resume at full speed.

This is the most dramatic demonstration of why you'd use drecs-native at all.

## Algorithm

For each particle `i` (run in parallel across threads, partitioned by row index):

```c
fx = 0; fy = 0
for j in [0, count):
    if j == i: continue
    dx = px[j] - px[i]
    dy = py[j] - py[i]
    r² = dx² + dy² + ε²        // ε = 1e-3, prevents singularities
    inv_r³ = 1 / (r² · √r²)
    fx += dx * inv_r³
    fy += dy * inv_r³

ax = G · fx        // G = 0.5, matches Ruby
ay = G · fy

// Semi-implicit Euler (more stable for orbits than explicit)
vx[i] += ax · dt
vy[i] += ay · dt
px[i] += vx[i] · dt
py[i] += vy[i] · dt

// Wrap so particles that fly off come back from the other edge
if px[i] < 0      px[i] += RES_W
elsif px[i] >= RES_W  px[i] -= RES_W
// (same for y)
```

Per-row cost: `O(N)` force evaluations × ~10 flops each = `~10·N` flops. At N=1500 that's 15,000 flops per row; 22.5 million flops per frame.

## Files

```
samples/nbody_gravity/
├── README.md
├── build.bat
└── app/
    ├── main.rb              # ECS setup, register system, render, debug, Ruby fallback
    └── nbody_kernel.c       # nbody_step kernel
```

## Related samples

- `samples/native_boids/` — light kernel, threading barely matters at default counts
- `samples/native_bench/` — heavy kernel (`expensive_force`, ~800 flops/row), shows the upper limit of threading speedup
- `samples/native_systems/` — minimal "two kernels + register" example

The three together form a progression: minimal API → realistic light kernel → realistic heavy kernel.