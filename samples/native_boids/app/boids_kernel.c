/*
 * boids_kernel.c - native kernels for the native_boids sample.
 *
 * Two kernels are provided:
 *
 *   1. boids_build_grid  (run with threads: 1)
 *      Builds a flat spatial grid of boid indices keyed by cell. Single
 *      threaded because the build is O(N) cheap work and parallelizing
 *      it would need atomics on per-cell counters.
 *
 *   2. boids_step        (run with threads: N)
 *      For each boid, scans 3x3 grid cells around it, accumulates
 *      separation / cohesion / alignment steering forces, clamps the
 *      velocity magnitude, integrates position with wrap-around.
 *      Per-row work is independent and embarrassingly parallel.
 *
 * The grid scratch lives in file-scope static storage and survives across
 * system calls, so we pay the allocation cost exactly once.
 *
 * Hard rules: see ext/drecs_kernel.h. Workers do not touch mrb_* and only
 * write to rows they own.
 *
 * IMPORTANT: grid constants below MUST match the Ruby side. The C kernel
 * does not know the Ruby values — if you change RESOLUTION, GRID_CELL_SIZE,
 * weights, etc. on the Ruby side, mirror them here.
 */

#include "drecs_kernel.h"
#include <math.h>
#include <string.h>

DRECS_DEFINE_STORAGE;

/* ---- Constants (mirror app/main.rb) ---- */

#define RES_W                1280.0
#define RES_H                720.0
#define GRID_CELL_SIZE       10.0
#define GRID_POS_FACTOR      (1.0 / GRID_CELL_SIZE)
#define GRID_COLS            128
#define GRID_ROWS            72
#define GRID_CELL_COUNT      (GRID_COLS * GRID_ROWS)

#define NEIGHBOUR_RANGE      10.0
#define NEIGHBOUR_RANGE_SQ   (NEIGHBOUR_RANGE * NEIGHBOUR_RANGE)
#define MAX_NEIGHBOURS       2          /* MOVEMENT_ACCURACY */
#define MIN_VELOCITY         2.0
#define MAX_VELOCITY         5.0
#define MIN_VELOCITY_SQ      (MIN_VELOCITY * MIN_VELOCITY)
#define MAX_VELOCITY_SQ      (MAX_VELOCITY * MAX_VELOCITY)

#define SEPARATION_WEIGHT    20.0
#define ALIGNMENT_WEIGHT     1.0
#define COHESION_WEIGHT      1.0
#define ALIGNMENT_DIVISOR    4.0
#define COHESION_DIVISOR     100.0

/* Max boids we store per grid cell before dropping into the void. Cells
 * hold an average of N/9216 boids; at N=50000 that's ~5.4 per cell. 32
 * gives generous headroom (~5.7x) without burning much memory.
 *
 * Total grid_indices size = GRID_CELL_COUNT * MAX_PER_CELL * sizeof(int)
 *                         = 9216 * 32 * 4 = ~1.18 MB.
 */
#define MAX_PER_CELL         32

/* ---- Static scratch (one process-wide grid, reused every frame) ---- */

static int s_grid_count[GRID_CELL_COUNT];
static int s_grid_start[GRID_CELL_COUNT];
static int s_grid_indices[GRID_CELL_COUNT * MAX_PER_CELL];

/* ---- Helpers ---- */

static inline int clamp_cell(int v, int hi) {
    if (v < 0) return 0;
    if (v >= hi) return hi - 1;
    return v;
}

/* ====================================================================
 * Kernel 1: boids_build_grid
 *
 * Reads:    Position.x, Position.y
 * Writes:   (none)
 * Threads:  1
 *
 * Layout: s_grid_count[c]  = number of boids in cell c
 *         s_grid_start[c]  = flat-array offset for cell c
 *         s_grid_indices[]  = packed boid indices, contiguous per cell
 *
 * Three passes:
 *   1. count    -- per-cell histogram (single threaded)
 *   2. prefix   -- exclusive scan of s_grid_count into s_grid_start
 *   3. scatter  -- re-walk positions, place index at start[cell]+cursor
 * ==================================================================== */

DRECS_KERNEL(boids_build_grid) {
    if (ctx->thread_id != 0) return;       /* only thread 0 does work */

    const double *px = ctx->in[0];
    const double *py = ctx->in[1];
    int count = ctx->count;

    /* Pass 1: count */
    memset(s_grid_count, 0, sizeof(s_grid_count));
    for (int i = 0; i < count; i++) {
        int cx = clamp_cell((int)(px[i] * GRID_POS_FACTOR), GRID_COLS);
        int cy = clamp_cell((int)(py[i] * GRID_POS_FACTOR), GRID_ROWS);
        s_grid_count[cx * GRID_ROWS + cy]++;
    }

    /* Pass 2: exclusive prefix sum */
    int sum = 0;
    for (int c = 0; c < GRID_CELL_COUNT; c++) {
        s_grid_start[c] = sum;
        sum += s_grid_count[c];
    }

    /* Pass 3: scatter, reusing s_grid_count as per-cell cursor */
    memset(s_grid_count, 0, sizeof(s_grid_count));
    for (int i = 0; i < count; i++) {
        int cx = clamp_cell((int)(px[i] * GRID_POS_FACTOR), GRID_COLS);
        int cy = clamp_cell((int)(py[i] * GRID_POS_FACTOR), GRID_ROWS);
        int cell = cx * GRID_ROWS + cy;
        int slot = s_grid_start[cell] + s_grid_count[cell];
        if (slot < GRID_CELL_COUNT * MAX_PER_CELL) {
            s_grid_indices[slot] = i;
            s_grid_count[cell]++;
        }
        /* overflow: cell held more than MAX_PER_CELL boids; the late
         * arrivals simply won't appear in the grid this frame, so they
         * won't influence their neighbours (and won't be influenced).
         * Acceptable trade-off for a fixed-size buffer.
         */
    }
}
DRECS_KERNEL_EXPORT(boids_build_grid)

/* ====================================================================
 * Kernel 2: boids_step
 *
 * Reads:    Position.x, Position.y, Velocity.x, Velocity.y
 * Writes:   Position.x, Position.y, Velocity.x, Velocity.y
 * Threads:  N (each worker owns its [start, end) row range)
 *
 * Algorithm (per row i in [start, end)):
 *   - Scan the 3x3 grid cells around i (read-only access to grid scratch).
 *   - Accumulate separation (1/d^2 away from close neighbours within range),
 *     cohesion (sum of positions, averaged minus self), alignment
 *     (sum of velocities, averaged minus self).
 *   - Stop accumulating once MAX_NEIGHBOURS neighbours have been seen.
 *   - Apply steering to velocity.
 *   - Clamp velocity magnitude to [MIN_VELOCITY, MAX_VELOCITY].
 *   - Integrate position with wrap-around.
 *   - Decay velocity by dt*100 (matches Ruby behaviour).
 *
 * Thread safety:
 *   - Each thread writes only to out[*][i] for i in its [start, end).
 *     No two threads touch the same (row, member) cell.
 *   - All threads read from in[*] (snapshot, read-only) and the grid
 *     scratch (populated by boids_build_grid before this kernel runs).
 * ==================================================================== */

DRECS_KERNEL(boids_step) {
    const double *px = ctx->in[0];
    const double *py = ctx->in[1];
    const double *vx = ctx->in[2];
    const double *vy = ctx->in[3];
    double *opx = ctx->out[0];
    double *opy = ctx->out[1];
    double *ovx = ctx->out[2];
    double *ovy = ctx->out[3];
    double dt = ctx->dt;
    double dt_scale = dt * 100.0;

    for (int i = ctx->start; i < ctx->end; i++) {
        double xi = px[i], yi = py[i];
        double ui = vx[i], vi = vy[i];

        int cx = clamp_cell((int)(xi * GRID_POS_FACTOR), GRID_COLS);
        int cy = clamp_cell((int)(yi * GRID_POS_FACTOR), GRID_ROWS);

        /* Accumulators. */
        double coh_x = 0.0, coh_y = 0.0;
        double sep_x = 0.0, sep_y = 0.0;
        double ali_x = 0.0, ali_y = 0.0;
        int n = 0;

        /* 3x3 cell scan; bail out once we hit MAX_NEIGHBOURS. */
        for (int dx = -1; dx <= 1 && n < MAX_NEIGHBOURS; dx++) {
            int ncx = cx + dx;
            if (ncx < 0 || ncx >= GRID_COLS) continue;
            for (int dy = -1; dy <= 1 && n < MAX_NEIGHBOURS; dy++) {
                int ncy = cy + dy;
                if (ncy < 0 || ncy >= GRID_ROWS) continue;
                int cell = ncx * GRID_ROWS + ncy;
                int cell_count = s_grid_count[cell];
                int cell_start = s_grid_start[cell];
                for (int k = 0; k < cell_count && n < MAX_NEIGHBOURS; k++) {
                    int j = s_grid_indices[cell_start + k];
                    if (j == i) continue;       /* skip self */
                    double dux = xi - px[j];
                    double duy = yi - py[j];
                    double d2 = dux * dux + duy * duy;
                    if (d2 < NEIGHBOUR_RANGE_SQ && d2 > 0.0) {
                        /* Separation vector: (self - other) / d^2.
                         * Skips the sqrt entirely — the constant factor
                         * is absorbed into SEPARATION_WEIGHT on Ruby side. */
                        double inv = 1.0 / d2;
                        sep_x += dux * inv;
                        sep_y += duy * inv;
                    }
                    coh_x += px[j];
                    coh_y += py[j];
                    ali_x += vx[j];
                    ali_y += vy[j];
                    n++;
                }
            }
        }

        if (n > 0) {
            /* Cohesion: (avg neighbour pos - self) / divisor * weight */
            coh_x = (coh_x / (double)n - xi) / COHESION_DIVISOR * COHESION_WEIGHT;
            coh_y = (coh_y / (double)n - yi) / COHESION_DIVISOR * COHESION_WEIGHT;

            sep_x *= SEPARATION_WEIGHT;
            sep_y *= SEPARATION_WEIGHT;

            /* Alignment: (avg neighbour vel - self vel) / divisor * weight */
            ali_x = (ali_x / (double)n - ui) / ALIGNMENT_DIVISOR * ALIGNMENT_WEIGHT;
            ali_y = (ali_y / (double)n - vi) / ALIGNMENT_DIVISOR * ALIGNMENT_WEIGHT;

            ui += coh_x + sep_x + ali_x;
            vi += coh_y + sep_y + ali_y;

            /* Clamp velocity magnitude. Theoretically speed2 could be 0
             * if steering forces exactly cancel the original velocity
             * (vanishingly rare but possible). Guard against it so we
             * never divide by zero and emit NaNs into the position. */
            double speed2 = ui * ui + vi * vi;
            if (speed2 > MAX_VELOCITY_SQ) {
                double scale = MAX_VELOCITY / sqrt(speed2);
                ui *= scale;
                vi *= scale;
            } else if (speed2 < MIN_VELOCITY_SQ) {
                if (speed2 > 0.0) {
                    double scale = MIN_VELOCITY / sqrt(speed2);
                    ui *= scale;
                    vi *= scale;
                } else {
                    /* Degenerate: pick an arbitrary unit direction. */
                    ui = MIN_VELOCITY;
                    vi = 0.0;
                }
            }
        }

        /* Integrate position with wrap-around (one frame's motion is well
         * under RES_W even at MAX_VELOCITY * dt_scale ~= 8.3 px). */
        xi += ui;
        yi += vi;
        if (xi < 0.0)        xi += RES_W;
        else if (xi >= RES_W) xi -= RES_W;
        if (yi < 0.0)        yi += RES_H;
        else if (yi >= RES_H) yi -= RES_H;

        /* Decay velocity by dt*100 (matches the Ruby sample exactly:
         * `vel.mul!(time.delta * 100)`). */
        ui *= dt_scale;
        vi *= dt_scale;

        opx[i] = xi;
        opy[i] = yi;
        ovx[i] = ui;
        ovy[i] = vi;
    }
}
DRECS_KERNEL_EXPORT(boids_step)

/* ---- Module registration ---- */

DRB_FFI_EXPORT
void drb_register_c_extensions_with_api(mrb_state *mrb, struct drb_api_t *api) {
    DRECS_INIT(api);
    struct RClass *mod = api->mrb_define_module(mrb, "BoidsKernel");
    DRECS_KERNEL_REGISTER(mrb, mod, boids_build_grid);
    DRECS_KERNEL_REGISTER(mrb, mod, boids_step);
}