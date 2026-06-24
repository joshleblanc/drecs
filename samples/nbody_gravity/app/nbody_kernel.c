/*
 * nbody_kernel.c - native kernel for the nbody_gravity sample.
 *
 * Single kernel: nbody_step. For each particle, sums gravitational
 * attraction from every other particle (O(N²) naive), then integrates
 * position+velocity with semi-implicit Euler.
 *
 * Per-row work scales naturally with N: a particle does N pair-force
 * evaluations per frame. That's the property that makes this a good
 * threading demo — at N=1500 each row is ~15000 flops, total ~22M
 * flops per frame, which is enough work to amortize the SDL thread
 * create/join overhead and show a real speedup.
 *
 * Hard rules: see ext/drecs_kernel.h. Workers do not touch mrb_* and
 * only write to rows they own.
 *
 * IMPORTANT: G (gravitational constant) and SOFTENING below MUST match
 * the Ruby side. They are not passed through the kernel context.
 */

#include "drecs_kernel.h"
#include <math.h>
#include <string.h>

DRECS_DEFINE_STORAGE;

/* ---- Constants (mirror app/main.rb) ---- */

#define RES_W                1280.0
#define RES_H                720.0

/* Gravitational constant. The real one (6.674e-11) is useless at game
 * scale; this is tuned to produce visible orbital motion at N=1500
 * particles in a 1280x720 space. Lower values let clusters spread
 * out, higher values collapse them faster. */
#define G                    0.5

/* Softening: epsilon added to r² in the force calculation so close
 * pairs don't produce singularities (and so the visual stays calm
 * when particles cluster). */
#define SOFTENING            1e-3
#define SOFTENING_SQ         (SOFTENING * SOFTENING)

/* ====================================================================
 * nbody_step
 *
 * Reads:    Position.x, Position.y, Velocity.x, Velocity.y
 * Writes:   Position.x, Position.y, Velocity.x, Velocity.y
 * Threads:  N (each worker owns its [start, end) row range)
 *
 * Per row i:
 *   fx, fy = 0
 *   for j in [0, count):
 *     if j == i: continue
 *     dx = px[j] - px[i]
 *     dy = py[j] - py[i]
 *     r² = dx² + dy² + SOFTENING²
 *     inv_r³ = 1 / (r² · √r²)         (this is r̂/|r|² in disguise)
 *     fx += dx * inv_r³
 *     fy += dy * inv_r³
 *   ax = G · fx
 *   ay = G · fy
 *   vx[i] += ax · dt
 *   vy[i] += ay · dt
 *   px[i] += vx[i] · dt
 *   py[i] += vy[i] · dt
 *   wrap around screen edges (so particles that fly off come back).
 *
 * Thread safety:
 *   - Each thread writes only to out[*][i] for i in its [start, end).
 *   - All threads read from in[*] (snapshot, read-only).
 *   - No shared mutable state between threads inside the kernel.
 *
 * Hot loop notes:
 *   - The inner `if (j == i) continue` skips ~1/N of iterations. With
 *     N=1500 that's 0.07% — negligible. Could be eliminated with a
 *     temporary swap but not worth the complexity here.
 *   - `-O2` will vectorize the inner loop and inline sqrt+div; on
 *     modern x86_64 you get one pair-force evaluation every ~5 ns.
 *     At N=1500 per row, that's ~7.5 µs per row, ~11 ms total per
 *     frame at 1 thread. 8 threads should bring this to ~1.4 ms.
 * ==================================================================== */

DRECS_KERNEL(nbody_step) {
    const double *px = ctx->in[0];
    const double *py = ctx->in[1];
    const double *vx = ctx->in[2];
    const double *vy = ctx->in[3];
    double *opx = ctx->out[0];
    double *opy = ctx->out[1];
    double *ovx = ctx->out[2];
    double *ovy = ctx->out[3];
    double dt = ctx->dt;
    int count = ctx->count;

    for (int i = ctx->start; i < ctx->end; i++) {
        double xi = px[i];
        double yi = py[i];
        double fx = 0.0;
        double fy = 0.0;

        for (int j = 0; j < count; j++) {
            if (j == i) continue;
            double dx = px[j] - xi;
            double dy = py[j] - yi;
            double r2 = dx * dx + dy * dy + SOFTENING_SQ;
            /* inv_r³ = 1 / (r² · √r²) = 1 / (r² · r) but we use sqrt to
             * avoid an extra multiply for the unit vector magnitude. */
            double inv_r3 = 1.0 / (r2 * sqrt(r2));
            fx += dx * inv_r3;
            fy += dy * inv_r3;
        }

        double ax = G * fx;
        double ay = G * fy;

        /* Semi-implicit Euler: update velocity first, then position
         * uses the new velocity. More stable than explicit Euler for
         * orbital systems. */
        double new_vx = vx[i] + ax * dt;
        double new_vy = vy[i] + ay * dt;
        double new_px = xi + new_vx * dt;
        double new_py = yi + new_vy * dt;

        /* Wrap so particles that fly off one edge come back from the
         * other. Not physically accurate (a particle at x=1 feels
         * gravity from a particle at x=1279 even though they're
         * actually close), but it keeps the demo on-screen and the
         * visual stays interesting. */
        if (new_px < 0.0)         new_px += RES_W;
        else if (new_px >= RES_W)  new_px -= RES_W;
        if (new_py < 0.0)         new_py += RES_H;
        else if (new_py >= RES_H)  new_py -= RES_H;

        opx[i] = new_px;
        opy[i] = new_py;
        ovx[i] = new_vx;
        ovy[i] = new_vy;
    }
}
DRECS_KERNEL_EXPORT(nbody_step)

/* ---- Module registration ---- */

DRB_FFI_EXPORT
void drb_register_c_extensions_with_api(mrb_state *mrb, struct drb_api_t *api) {
    DRECS_INIT(api);
    struct RClass *mod = api->mrb_define_module(mrb, "NBodyKernel");
    DRECS_KERNEL_REGISTER(mrb, mod, nbody_step);
}