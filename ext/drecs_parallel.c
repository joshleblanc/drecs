/*
 * drecs_parallel.c
 *
 * The drecs parallel runtime. Loaded into DragonRuby with `DR.dlopen`.
 *
 * Exposes Drecs::Parallel module functions used by drecs's Ruby side to:
 *   - report hardware thread count
 *   - run a user-supplied native kernel across N SDL3 threads, given
 *     pre-extracted SoA input arrays and same-shape output arrays
 *
 * The user kernel is a plain C function pointer (drecs_kernel_fn) obtained
 * from the user's own DragonRuby C extension via a getter thunk produced
 * by the DRECS_KERNEL_EXPORT macro in drecs_kernel.h.
 *
 * IMPORTANT: worker threads run pure C only. No mrb_* calls happen on
 * a worker. All Ruby <-> C marshaling is done on the main thread before
 * fan-out and after join.
 *
 * Build note for Windows (mingw-w64):
 *   The Ruby -> C dispatch on x86_64 expects 16-byte stack alignment at
 *   the callee's first instruction. mingw-w64 by default doesn't realign
 *   on function entry, so the first SSE/AVX instruction in a called
 *   function segfaults before any of our own code runs. Marking the
 *   exported method with __attribute__((force_align_arg_pointer)) inserts
 *   an `and rsp, -16` prologue that fixes this. Without this attribute,
 *   `m_run_kernel` appears never to be entered.
 *
 * Format-string note for mrb_get_args:
 *   Use `A` (capital A, Array as mrb_value*) for arrays — not `a`
 *   (lowercase, requires BOTH (mrb_value*, mrb_int)). Lowercase `a`
 *   would consume the next variadic slot as the length, corrupting
 *   in_arrays/out_arrays. Use `o` for any-object slots (Integer / String /
 *   Float / etc.) where you want to decode the type yourself.
 */

#include <dragonruby.h>
#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/string.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- Mirror of the public ABI from drecs_kernel.h. Keep in sync. ---- */

typedef struct drecs_kernel_ctx {
    int start, end;
    int count;
    int thread_id, thread_count;
    double dt;
    void  *user;
    const double * const *in;
    double       * const *out;
    int in_count, out_count;
} drecs_kernel_ctx;

typedef void (*drecs_kernel_fn)(const drecs_kernel_ctx *ctx);

/* ---------------------------------------------------------------------- */

static struct drb_api_t *drb;

typedef struct {
    drecs_kernel_fn fn;
    drecs_kernel_ctx ctx;
} WorkerSlot;

static int worker_main(void *p) {
    WorkerSlot *w = (WorkerSlot *)p;
    w->fn(&w->ctx);
    return 0;
}

/* Convert mrb_value -> double. Accepts Float and Integer; anything
 * else becomes 0.0 (kernels operate on numerics only). */
static inline double to_double(mrb_state *mrb, mrb_value v) {
    (void)mrb;
    if (mrb_float_p(v)) return mrb_float(v);
    if (mrb_fixnum_p(v)) return (double)mrb_fixnum(v);
    return 0.0;
}

/* ---------------- Drecs::Parallel.init ---------------- */
static mrb_value m_init(mrb_state *mrb, mrb_value self) {
    (void)mrb; (void)self;
    return mrb_true_value();
}

/* ---------------- Drecs::Parallel.hardware_threads ---------------- */
static mrb_value m_hardware_threads(mrb_state *mrb, mrb_value self) {
    (void)mrb; (void)self;
    /* drb_api_t doesn't expose a CPU-count helper in DR7; pick a sane
     * default and let users override at register_native_system time. */
    return mrb_fixnum_value(4);
}

/*
 * Drecs::Parallel.run_kernel(fn_cptr, in_arrays, out_arrays, count, dt, threads)
 *
 *   fn_cptr     : Integer or 8-byte String. The runtime expects an opaque
 *                 kernel pointer; some DragonRuby builds encode the result
 *                 of mrb_int_value(mrb, intptr_t) as a raw String rather
 *                 than a boxed Integer when the value is pointer-sized.
 *                 We accept both forms.
 *   in_arrays   : Array<Array<Numeric>> of length in_count, each `count` long
 *   out_arrays  : Array<Array> of length out_count, each `count` long
 *                 (will be overwritten in place with kernel results)
 *   count       : Integer, number of rows
 *   dt          : Float, user scalar
 *   threads     : Integer, max worker threads (clamped to count)
 *
 * Returns nil. Raises on shape mismatch or null kernel pointer.
 */
static mrb_value m_run_kernel(mrb_state *mrb, mrb_value self)
    __attribute__((force_align_arg_pointer));
static mrb_value m_run_kernel(mrb_state *mrb, mrb_value self) {
    (void)self;

    mrb_value in_arrays, out_arrays, dt_val, fn_val;
    mrb_int count, threads;

    /* Format `oAAioi`:
     *   `o` = any Object as mrb_value*   (fn_cptr — Integer or String)
     *   `A` = Array as mrb_value*        (in_arrays)
     *   `A` = Array as mrb_value*        (out_arrays)
     *   `i` = Integer as mrb_int*        (count)
     *   `o` = any Object as mrb_value*   (dt — Float or Integer)
     *   `i` = Integer as mrb_int*        (threads)
     */
    drb->mrb_get_args(mrb, "oAAioi",
                      &fn_val, &in_arrays, &out_arrays,
                      &count, &dt_val, &threads);

    /* Decode the kernel pointer. */
    intptr_t fn_int = 0;
    if (mrb_integer_p(fn_val)) {
        fn_int = (intptr_t)mrb_integer(fn_val);
    } else if (mrb_string_p(fn_val)) {
        const char *p = drb->mrb_string_value_ptr(mrb, fn_val);
        mrb_int len  = drb->mrb_string_value_len(mrb, fn_val);
        if (len < (mrb_int)sizeof(intptr_t)) {
            drb->mrb_raise(mrb, drb->drb_getruntime_error(mrb),
                           "drecs: kernel pointer string too short");
            return mrb_nil_value();
        }
        for (size_t i = 0; i < sizeof(intptr_t); i++) {
            fn_int |= ((intptr_t)(unsigned char)p[i]) << (i * 8);
        }
    } else {
        drb->mrb_raise(mrb, drb->drb_getruntime_error(mrb),
                       "drecs: kernel pointer must be Integer or String");
        return mrb_nil_value();
    }

    if (count <= 0) return mrb_nil_value();
    if (threads < 1) threads = 1;
    if (threads > count) threads = (int)count;

    drecs_kernel_fn fn = (drecs_kernel_fn)fn_int;
    if (!fn) {
        drb->mrb_raise(mrb, drb->drb_getruntime_error(mrb),
                       "drecs: null kernel pointer");
        return mrb_nil_value();
    }

    int in_count  = (int)RARRAY_LEN(in_arrays);
    int out_count = (int)RARRAY_LEN(out_arrays);

    /* Validate inner array lengths. */
    for (int i = 0; i < in_count; i++) {
        mrb_value a = RARRAY_PTR(in_arrays)[i];
        if ((int)RARRAY_LEN(a) != (int)count) {
            drb->mrb_raise(mrb, drb->drb_getruntime_error(mrb),
                           "drecs: input array length mismatch");
            return mrb_nil_value();
        }
    }
    for (int i = 0; i < out_count; i++) {
        mrb_value a = RARRAY_PTR(out_arrays)[i];
        if ((int)RARRAY_LEN(a) != (int)count) {
            drb->mrb_raise(mrb, drb->drb_getruntime_error(mrb),
                           "drecs: output array length mismatch");
            return mrb_nil_value();
        }
    }

    /* Allocate SoA buffers and pointer tables. */
    size_t row_bytes = (size_t)count * sizeof(double);
    double **in_bufs  = NULL;
    double **out_bufs = NULL;
    if (in_count > 0) {
        in_bufs = (double **)drb->mrb_malloc(mrb, in_count * sizeof(double *));
        for (int i = 0; i < in_count; i++) {
            in_bufs[i] = (double *)drb->mrb_malloc(mrb, row_bytes);
            mrb_value a = RARRAY_PTR(in_arrays)[i];
            mrb_value *items = RARRAY_PTR(a);
            for (int r = 0; r < (int)count; r++) {
                in_bufs[i][r] = to_double(mrb, items[r]);
            }
        }
    }
    if (out_count > 0) {
        out_bufs = (double **)drb->mrb_malloc(mrb, out_count * sizeof(double *));
        for (int i = 0; i < out_count; i++) {
            out_bufs[i] = (double *)drb->mrb_malloc(mrb, row_bytes);
            /* Seed outputs with current Ruby values so kernels that only
             * read-modify-write a subset of rows still produce correct
             * writeback. */
            mrb_value a = RARRAY_PTR(out_arrays)[i];
            mrb_value *items = RARRAY_PTR(a);
            for (int r = 0; r < (int)count; r++) {
                out_bufs[i][r] = to_double(mrb, items[r]);
            }
        }
    }

    /* Partition and dispatch. */
    int nthreads = (int)threads;
    int chunk = ((int)count + nthreads - 1) / nthreads;
    double dt = to_double(mrb, dt_val);

    if (nthreads <= 1) {
        drecs_kernel_ctx ctx;
        ctx.start = 0; ctx.end = (int)count; ctx.count = (int)count;
        ctx.thread_id = 0; ctx.thread_count = 1;
        ctx.dt = dt; ctx.user = NULL;
        ctx.in = (const double * const *)in_bufs;
        ctx.out = out_bufs;
        ctx.in_count = in_count; ctx.out_count = out_count;
        fn(&ctx);
    } else {
        WorkerSlot *slots = (WorkerSlot *)drb->mrb_malloc(mrb, nthreads * sizeof(WorkerSlot));
        SDL_Thread **ths = (SDL_Thread **)drb->mrb_malloc(mrb, nthreads * sizeof(SDL_Thread *));

        for (int t = 0; t < nthreads; t++) {
            int s = t * chunk;
            int e = s + chunk;
            if (e > (int)count) e = (int)count;
            slots[t].fn = fn;
            slots[t].ctx.start = s;
            slots[t].ctx.end = e;
            slots[t].ctx.count = (int)count;
            slots[t].ctx.thread_id = t;
            slots[t].ctx.thread_count = nthreads;
            slots[t].ctx.dt = dt;
            slots[t].ctx.user = NULL;
            slots[t].ctx.in = (const double * const *)in_bufs;
            slots[t].ctx.out = out_bufs;
            slots[t].ctx.in_count = in_count;
            slots[t].ctx.out_count = out_count;

            char name[32];
            snprintf(name, sizeof(name), "drecs_w%d", t);
            ths[t] = drb->SDL_CreateThread(worker_main, name, &slots[t]);
        }
        for (int t = 0; t < nthreads; t++) {
            if (ths[t]) drb->SDL_WaitThread(ths[t], NULL);
        }
        drb->mrb_free(mrb, ths);
        drb->mrb_free(mrb, slots);
    }

    /* Writeback: stamp out_bufs into the Ruby output arrays. */
    for (int i = 0; i < out_count; i++) {
        mrb_value a = RARRAY_PTR(out_arrays)[i];
        mrb_value *items = RARRAY_PTR(a);
        double *src = out_bufs[i];
        for (int r = 0; r < (int)count; r++) {
            items[r] = drb->mrb_float_value(mrb, src[r]);
        }
    }

    /* Free buffers. */
    for (int i = 0; i < in_count; i++)  drb->mrb_free(mrb, in_bufs[i]);
    for (int i = 0; i < out_count; i++) drb->mrb_free(mrb, out_bufs[i]);
    if (in_bufs)  drb->mrb_free(mrb, in_bufs);
    if (out_bufs) drb->mrb_free(mrb, out_bufs);

    return mrb_nil_value();
}

/* ---------------- Registration ---------------- */
DRB_FFI_EXPORT
void drb_register_c_extensions_with_api(mrb_state *mrb, struct drb_api_t *api) {
    drb = api;

    struct RClass *drecs_module = drb->mrb_module_get(mrb, "Drecs");
    if (!drecs_module) drecs_module = drb->mrb_define_module(mrb, "Drecs");

    struct RClass *parallel = drb->mrb_define_module_under(mrb, drecs_module, "Parallel");

    drb->mrb_define_module_function(mrb, parallel, "init",
                                    m_init, MRB_ARGS_NONE());
    drb->mrb_define_module_function(mrb, parallel, "hardware_threads",
                                    m_hardware_threads, MRB_ARGS_NONE());
    drb->mrb_define_module_function(mrb, parallel, "run_kernel",
                                    m_run_kernel, MRB_ARGS_REQ(6));

    drb->mrb_define_const(mrb, parallel, "AVAILABLE", mrb_true_value());
}
