/*
 * my_systems.c - Example user-authored native ECS systems.
 *
 * Build (from this directory):
 *   gcc -shared -fPIC -O2 -I../../../../include \
 *       -I../../../ext \
 *       -o native/<platform>/my_systems.<ext> my_systems.c
 *
 * On Windows-x64 with mingw gcc:
 *   gcc -shared -O2 -I../../../../include -I../../../ext \
 *       -o native/windows-amd64/my_systems.dll my_systems.c
 */

#include "drecs_kernel.h"

DRECS_DEFINE_STORAGE;

/* Integrate position from velocity over dt. */
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

/* Apply linear damping to velocity: v *= (1 - damping*dt). */
DRECS_KERNEL(damp_velocity) {
    const double *vx = ctx->in[0];
    const double *vy = ctx->in[1];
    double *ovx = ctx->out[0];
    double *ovy = ctx->out[1];
    double k = 1.0 - 0.5 * ctx->dt;   /* hard-coded damping for the demo */
    if (k < 0.0) k = 0.0;
    for (int i = ctx->start; i < ctx->end; i++) {
        ovx[i] = vx[i] * k;
        ovy[i] = vy[i] * k;
    }
}
DRECS_KERNEL_EXPORT(damp_velocity)

DRB_FFI_EXPORT
void drb_register_c_extensions_with_api(mrb_state *mrb, struct drb_api_t *api) {
    DRECS_INIT(api);
    struct RClass *mod = api->mrb_define_module(mrb, "MySystems");
    DRECS_KERNEL_REGISTER(mrb, mod, integrate_motion);
    DRECS_KERNEL_REGISTER(mrb, mod, damp_velocity);
}
