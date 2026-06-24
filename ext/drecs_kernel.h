/*
 * drecs_kernel.h - Public header for user-authored native ECS systems.
 *
 * Drop this header into your DragonRuby C extension to write parallel
 * ECS systems that drecs will run across multiple SDL3 threads.
 *
 * The drecs runtime owns:
 *   - matching archetypes
 *   - extracting component members into SoA double* buffers (main thread)
 *   - partitioning work across N threads
 *   - calling your kernel once per worker with a row range
 *   - writing your output buffers back into the Ruby component structs
 *   - bumping change ticks for written components
 *
 * Your kernel owns:
 *   - a tight loop from ctx->start to ctx->end
 *   - reading ctx->in[i][row] inputs
 *   - writing ctx->out[i][row] outputs
 *
 * Hard rules inside a kernel:
 *   - Do NOT call any mrb_* API. mruby is single-threaded.
 *   - Do NOT allocate Ruby objects, raise, or call back into Ruby.
 *   - Do NOT write outside [ctx->start, ctx->end). Other threads own those rows.
 *   - Do NOT write to ctx->in[*]. They are inputs.
 *   - libc / SDL primitives / your own thread-local state are fine.
 *
 * Minimal example:
 *
 *   #include "drecs_kernel.h"
 *
 *   DRECS_KERNEL(integrate_motion) {
 *       const double *px = ctx->in[0], *py = ctx->in[1];
 *       const double *vx = ctx->in[2], *vy = ctx->in[3];
 *       double *opx = ctx->out[0], *opy = ctx->out[1];
 *       double dt = ctx->dt;
 *       for (int i = ctx->start; i < ctx->end; i++) {
 *           opx[i] = px[i] + vx[i] * dt;
 *           opy[i] = py[i] + vy[i] * dt;
 *       }
 *   }
 *   DRECS_KERNEL_EXPORT(integrate_motion)
 *
 *   DRB_FFI_EXPORT
 *   void drb_register_c_extensions_with_api(mrb_state *mrb, struct drb_api_t *api) {
 *       DRECS_INIT(api);
 *       struct RClass *mod = api->mrb_define_module(mrb, "MySystems");
 *       DRECS_KERNEL_REGISTER(mrb, mod, integrate_motion);
 *   }
 *
 * On the Ruby side:
 *
 *   DR.dlopen "drecs_parallel"   # drecs runtime
 *   DR.dlopen "my_systems"       # your kernels
 *   Drecs::Parallel.load
 *
 *   world.register_native_system(
 *     :integrate,
 *     module_name: "MySystems",
 *     kernel:      :integrate_motion,
 *     reads:       [[Position, :x], [Position, :y], [Velocity, :x], [Velocity, :y]],
 *     writes:      [[Position, :x], [Position, :y]],
 *     threads:     4,
 *   )
 *
 *   world.run_native_system(:integrate, dt: 1.0/60.0)
 */

#ifndef DRECS_KERNEL_H
#define DRECS_KERNEL_H

#include <dragonruby.h>
#include <mruby.h>
#include <mruby/class.h>
#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Per-call context handed to a kernel. Workers receive a per-thread copy
 * with their own start/end; everything else is shared (read-only from
 * the kernel's perspective). */
typedef struct drecs_kernel_ctx {
    int start;          /* first row this worker owns (inclusive)        */
    int end;            /* one past last row this worker owns            */
    int count;          /* total rows in the archetype slice             */
    int thread_id;      /* 0..thread_count-1                              */
    int thread_count;   /* number of threads cooperating on this call    */

    double dt;          /* user-supplied scalar (delta time, etc.)        */
    void  *user;        /* user-supplied opaque pointer (or NULL)         */

    const double * const *in;   /* in[i] is a double[count] input buffer  */
    double       * const *out;  /* out[i] is a double[count] output buffer*/
    int in_count;
    int out_count;
} drecs_kernel_ctx;

typedef void (*drecs_kernel_fn)(const drecs_kernel_ctx *ctx);

/* Internal: holds the drb_api_t* shared by all kernel-getter thunks in
 * this extension. Set by DRECS_INIT. */
extern struct drb_api_t *_drecs_drb_api;

#define DRECS_INIT(api_ptr) do { _drecs_drb_api = (api_ptr); } while (0)

/* Define the static storage for _drecs_drb_api. Place this at file scope
 * exactly once per user extension (DRECS_KERNEL_EXPORT_STORAGE), or just
 * include this header which provides it as a weak-style definition. */
#define DRECS_DEFINE_STORAGE struct drb_api_t *_drecs_drb_api = 0

/* Declare a kernel function. */
#define DRECS_KERNEL(name) \
    static void name(const drecs_kernel_ctx *ctx)

/* Generate the Ruby-callable thunk that returns the address of `fn`
 * encoded as a 64-bit integer via mrb_int_value (the safe boxing-aware
 * encoder in DragonRuby's mruby). Place at file scope after the
 * DRECS_KERNEL definition. */
#define DRECS_KERNEL_EXPORT(fn)                                              \
    static mrb_value _drecs_getptr_##fn(mrb_state *mrb, mrb_value self) {    \
        (void)self;                                                          \
        char _drecs_msg[160];                                                \
        snprintf(_drecs_msg, sizeof(_drecs_msg),                             \
                 "* INFO - drecs: getter %s called, fn=0x%llx",              \
                 #fn, (unsigned long long)(uintptr_t)&fn);                   \
        _drecs_drb_api->drb_log_write("Drecs", 0, _drecs_msg);               \
        return _drecs_drb_api->mrb_int_value(                                \
            mrb, (mrb_int)(intptr_t)&fn);                                    \
    }

/* Register the thunk on the given mruby module under the conventional
 * name "_kernel_<fn>". drecs's Ruby loader looks it up by that name. */
#define DRECS_KERNEL_REGISTER(mrb_state_ptr, mod, fn)                        \
    _drecs_drb_api->mrb_define_module_function(                              \
        (mrb_state_ptr), (mod), "_kernel_" #fn,                              \
        _drecs_getptr_##fn, MRB_ARGS_NONE())

#ifdef __cplusplus
}
#endif

#endif /* DRECS_KERNEL_H */
