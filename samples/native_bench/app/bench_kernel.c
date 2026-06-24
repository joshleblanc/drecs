/* bench_kernel.c — kernels for the native_bench sample.
 *
 * Build with build.bat. Three kernels are provided:
 *   - integrate_motion : position += velocity * dt (matches my_systems.c)
 *   - damp_velocity    : velocity *= (1 - 0.5 * dt)
 *   - expensive_force  : 100 inner iterations of spring-damper per row
 *                        (verlet integrate toward origin with damping).
 *                        This is the "heavy" kernel that lets us test
 *                        whether native threading pays off when the
 *                        per-row compute dwarfs the marshal overhead.
 *
 * The benchmark in main.rb compares Ruby vs native at multiple entity
 * counts and thread counts, and reports per-iteration timing +
 * correctness vs the Ruby reference.
 */

#include "drecs_kernel.h"

DRECS_DEFINE_STORAGE;

DRECS_KERNEL(integrate_motion) {
    const double *px = ctx->in[0];
    const double *py = ctx->in[1];
    const double *vx = ctx->in[2];
    const double *vy = ctx->in[3];
    double *opx = ctx->out[0];
    double *opy = ctx->out[1];
    double dt = ctx->dt;

    for (int i = ctx->start; i < ctx->end; i++) {
        opx[i] = px[i] + vx[i] * dt;
        opy[i] = py[i] + vy[i] * dt;
    }
}
DRECS_KERNEL_EXPORT(integrate_motion)

DRECS_KERNEL(damp_velocity) {
    const double *vx = ctx->in[0];
    const double *vy = ctx->in[1];
    double *ovx = ctx->out[0];
    double *ovy = ctx->out[1];
    double k = 1.0 - 0.5 * ctx->dt;
    if (k < 0.0) k = 0.0;
    for (int i = ctx->start; i < ctx->end; i++) {
        ovx[i] = vx[i] * k;
        ovy[i] = vy[i] * k;
    }
}
DRECS_KERNEL_EXPORT(damp_velocity)

/* Heavy: 100 substeps of spring-damper verlet per row.
 *
 * Reads pos.x, pos.y, vel.x, vel.y.
 * Writes vel.x, vel.y (position changes are throwaway locals).
 *
 * Per-row work: 100 iters * (~8 floating-point ops + 1 transcendent if
 * desired) ≈ 800-1600 ops. At 50k rows that's ~50M ops per call —
 * enough that the marshal overhead (~2-3 ms) should be amortized.
 */
DRECS_KERNEL(expensive_force) {
    const double *px = ctx->in[0];
    const double *py = ctx->in[1];
    const double *vx = ctx->in[2];
    const double *vy = ctx->in[3];
    double *ovx = ctx->out[0];
    double *ovy = ctx->out[1];
    double dt = ctx->dt;
    double dt_sub = dt / 100.0;

    for (int i = ctx->start; i < ctx->end; i++) {
        double x = px[i];
        double y = py[i];
        double u = vx[i];
        double v = vy[i];
        for (int k = 0; k < 100; k++) {
            double fx = -0.5 * x;
            double fy = -0.5 * y;
            u += fx * dt_sub;
            v += fy * dt_sub;
            x += u  * dt_sub;
            y += v  * dt_sub;
            u *= 0.999;
            v *= 0.999;
        }
        ovx[i] = u;
        ovy[i] = v;
    }
}
DRECS_KERNEL_EXPORT(expensive_force)

DRB_FFI_EXPORT
void drb_register_c_extensions_with_api(mrb_state *mrb, struct drb_api_t *api) {
    DRECS_INIT(api);
    struct RClass *mod = api->mrb_define_module(mrb, "BenchSystems");
    DRECS_KERNEL_REGISTER(mrb, mod, integrate_motion);
    DRECS_KERNEL_REGISTER(mrb, mod, damp_velocity);
    DRECS_KERNEL_REGISTER(mrb, mod, expensive_force);
}

