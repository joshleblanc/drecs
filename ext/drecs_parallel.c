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
#include <mruby/hash.h>
#include <mruby/string.h>
#include <mruby/variable.h>
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
 * Drecs::Parallel.run_kernel_native(fn_cptr, in_stores, in_members, out_stores, out_members, count, dt, threads)
 *
 *   fn_cptr      : Integer or 8-byte String. The runtime expects an opaque
 *                  kernel pointer; some DragonRuby builds encode the result
 *                  of mrb_int_value(mrb, intptr_t) as a raw String rather
 *                  than a boxed Integer when the value is pointer-sized.
 *                  We accept both forms.
 *   in_stores    : Array<Array<Struct>>. One inner Array per input, each
 *                  inner Array holds drecs component Struct instances.
 *   in_members   : Array<Symbol|String>. One member name per input.
 *   out_stores   : Array<Array<Struct>>. Same shape as in_stores.
 *   out_members  : Array<Symbol|String>. Same shape as in_members.
 *   count        : Integer, number of rows.
 *   dt           : Float or Integer, user scalar.
 *   threads      : Integer, max worker threads (clamped to count).
 *
 *   This is the high-throughput variant of run_kernel: instead of asking
 *   the Ruby side to pre-build a 2D Numeric array via store[i].send(:x)
 *   (which costs ~300ns per row in mruby), we read the struct members
 *   in C via mrb_iv_get (~50ns per row). At N=20000 the SoA extraction
 *   drops from ~96ms/frame to ~8ms/frame — the difference between 11fps
 *   and 60fps on the boids workload.
 *
 *   Returns nil. Raises on shape mismatch or null kernel pointer.
 */
static mrb_value m_run_kernel_native(mrb_state *mrb, mrb_value self)
    __attribute__((force_align_arg_pointer));
static mrb_value m_run_kernel_native(mrb_state *mrb, mrb_value self) {
    (void)self;

    mrb_value in_stores_v, in_members_v, out_stores_v, out_members_v, dt_val, fn_val;
    mrb_int count, threads;

    /* Format "oAAAAioi":
     *   o  Object (fn_cptr — Integer or String)
     *   A  Array (in_stores — Array<Array<Struct>>)
     *   A  Array (in_members — Array<Symbol|String>)
     *   A  Array (out_stores)
     *   A  Array (out_members)
     *   i  Integer (count)
     *   o  Object (dt — Float or Integer)
     *   i  Integer (threads)
     *
     * NOTE: count uses `i` (Integer only) and dt uses `o` (any object).
     * mrb_get_args raises ArgumentError if `i` is asked for a Float —
     * do NOT swap count and dt slots here without also swapping their
     * format chars.
     */
    drb->mrb_get_args(mrb, "oAAAAioi",
                      &fn_val,
                      &in_stores_v, &in_members_v,
                      &out_stores_v, &out_members_v,
                      &count, &dt_val, &threads);

    /* Decode the kernel pointer (same as m_run_kernel). */
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

    int in_count  = (int)RARRAY_LEN(in_stores_v);
    int out_count = (int)RARRAY_LEN(out_stores_v);
    if (in_count != (int)RARRAY_LEN(in_members_v)) {
        drb->mrb_raise(mrb, drb->drb_getruntime_error(mrb),
                       "drecs: in_stores / in_members length mismatch");
        return mrb_nil_value();
    }
    if (out_count != (int)RARRAY_LEN(out_members_v)) {
        drb->mrb_raise(mrb, drb->drb_getruntime_error(mrb),
                       "drecs: out_stores / out_members length mismatch");
        return mrb_nil_value();
    }

    /* Resolve member names to mrb_sym once (avoids per-row string→sym cost).
     *
     * The Ruby side passes accessor names like :x (the public method name).
     * We need the IVAR name to look up the storage — mruby stores
     * instance variables under the @-prefixed symbol form, so
     * `instance_variable_set(:@x, v)` writes to symbol `:@x`. Pass `:x`
     * to `mrb_iv_get` and you get nil. We build the @-prefixed name here
     * so per-row reads/writes are O(1) ivar lookups, not method dispatch.
     */
    char ivar_buf[64];
    mrb_sym *in_syms  = (mrb_sym *)drb->mrb_malloc(mrb, sizeof(mrb_sym) * (in_count  > 0 ? in_count  : 1));
    mrb_sym *out_syms = (mrb_sym *)drb->mrb_malloc(mrb, sizeof(mrb_sym) * (out_count > 0 ? out_count : 1));
    for (int i = 0; i < in_count; i++) {
        mrb_value mv = RARRAY_PTR(in_members_v)[i];
        const char *cs = NULL;
        if (mrb_type(mv) == MRB_TT_SYMBOL) {
            cs = drb->mrb_sym_name(mrb, mrb_symbol(mv));
        } else if (mrb_type(mv) == MRB_TT_STRING) {
            cs = drb->mrb_string_value_cstr(mrb, &mv);
        } else {
            drb->mrb_free(mrb, in_syms); drb->mrb_free(mrb, out_syms);
            drb->mrb_raise(mrb, drb->drb_getruntime_error(mrb),
                           "drecs: in_members must be Symbols or Strings");
            return mrb_nil_value();
        }
        if (!cs) cs = "";
        snprintf(ivar_buf, sizeof(ivar_buf), "@%s", cs);
        in_syms[i] = drb->mrb_intern_cstr(mrb, ivar_buf);
    }
    for (int i = 0; i < out_count; i++) {
        mrb_value mv = RARRAY_PTR(out_members_v)[i];
        const char *cs = NULL;
        if (mrb_type(mv) == MRB_TT_SYMBOL) {
            cs = drb->mrb_sym_name(mrb, mrb_symbol(mv));
        } else if (mrb_type(mv) == MRB_TT_STRING) {
            cs = drb->mrb_string_value_cstr(mrb, &mv);
        } else {
            drb->mrb_free(mrb, in_syms); drb->mrb_free(mrb, out_syms);
            drb->mrb_raise(mrb, drb->drb_getruntime_error(mrb),
                           "drecs: out_members must be Symbols or Strings");
            return mrb_nil_value();
        }
        if (!cs) cs = "";
        snprintf(ivar_buf, sizeof(ivar_buf), "@%s", cs);
        out_syms[i] = drb->mrb_intern_cstr(mrb, ivar_buf);
    }

    /* Get store array pointers. */
    mrb_value *in_store_items  = in_count  ? RARRAY_PTR(in_stores_v)  : NULL;
    mrb_value *out_store_items = out_count ? RARRAY_PTR(out_stores_v) : NULL;
    mrb_value **in_arrays  = (mrb_value **)drb->mrb_malloc(mrb, sizeof(mrb_value *) * (in_count  > 0 ? in_count  : 1));
    mrb_value **out_arrays = (mrb_value **)drb->mrb_malloc(mrb, sizeof(mrb_value *) * (out_count > 0 ? out_count : 1));
    for (int i = 0; i < in_count; i++) {
        in_arrays[i] = RARRAY_PTR(in_store_items[i]);
    }
    for (int i = 0; i < out_count; i++) {
        out_arrays[i] = RARRAY_PTR(out_store_items[i]);
    }

    /* Allocate SoA buffers and extract input / seed output. */
    size_t row_bytes = (size_t)count * sizeof(double);
    double **in_bufs  = NULL;
    double **out_bufs = NULL;
    if (in_count > 0) {
        in_bufs = (double **)drb->mrb_malloc(mrb, in_count * sizeof(double *));
        for (int i = 0; i < in_count; i++) {
            in_bufs[i] = (double *)drb->mrb_malloc(mrb, row_bytes);
            mrb_value *items = in_arrays[i];
            mrb_sym sym = in_syms[i];
            for (int r = 0; r < (int)count; r++) {
                in_bufs[i][r] = to_double(mrb, drb->mrb_iv_get(mrb, items[r], sym));
            }
        }
    }
    if (out_count > 0) {
        out_bufs = (double **)drb->mrb_malloc(mrb, out_count * sizeof(double *));
        for (int i = 0; i < out_count; i++) {
            out_bufs[i] = (double *)drb->mrb_malloc(mrb, row_bytes);
            mrb_value *items = out_arrays[i];
            mrb_sym sym = out_syms[i];
            for (int r = 0; r < (int)count; r++) {
                out_bufs[i][r] = to_double(mrb, drb->mrb_iv_get(mrb, items[r], sym));
            }
        }
    }

    /* Partition and dispatch (identical to m_run_kernel). */
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
            snprintf(name, sizeof(name), "drecs_n%d", t);
            ths[t] = drb->SDL_CreateThread(worker_main, name, &slots[t]);
        }
        for (int t = 0; t < nthreads; t++) {
            if (ths[t]) drb->SDL_WaitThread(ths[t], NULL);
        }
        drb->mrb_free(mrb, ths);
        drb->mrb_free(mrb, slots);
    }

    /* Writeback: stamp out_bufs into the Ruby struct iVars and set the
     * mrb_value to a fresh float. Setting the iVar on a Struct subclass
     * also updates the .member accessor output. */
    for (int i = 0; i < out_count; i++) {
        mrb_value *items = out_arrays[i];
        mrb_sym sym = out_syms[i];
        double *src = out_bufs[i];
        for (int r = 0; r < (int)count; r++) {
            drb->mrb_iv_set(mrb, items[r], sym,
                            drb->mrb_float_value(mrb, src[r]));
        }
    }

    /* Free buffers. */
    for (int i = 0; i < in_count; i++)  drb->mrb_free(mrb, in_bufs[i]);
    for (int i = 0; i < out_count; i++) drb->mrb_free(mrb, out_bufs[i]);
    if (in_bufs)  drb->mrb_free(mrb, in_bufs);
    if (out_bufs) drb->mrb_free(mrb, out_bufs);
    drb->mrb_free(mrb, in_arrays);
    drb->mrb_free(mrb, out_arrays);
    drb->mrb_free(mrb, in_syms);
    drb->mrb_free(mrb, out_syms);

    return mrb_nil_value();
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

/* ---------------- Drecs::Parallel.each_row ---------------- */

/*
 * Drecs::Parallel.each_row(entity_ids, stores, &block)
 *
 *   entity_ids : Array<Integer>     aligned with stores by row index
 *   stores     : Array<Array>        one inner array per component class;
 *                                  each inner array holds the components in
 *                                  row order, aligned with entity_ids
 *   block      : required Proc       called once per row as
 *                                  block.call(entity_ids[i], stores[0][i], ...)
 *
 * Specialized per-component-count for the common 0-4 case so we never
 * allocate an args array in the inner loop. At 40k entities × 60fps the
 * pure-Ruby `while i < len ... case num_stores ... yield ... end` loop
 * spends ~480ms/sec on iteration framing alone — this function replaces
 * the loop body with a C `for` so all that's left in Ruby is the user's
 * block dispatch.
 *
 * Returns nil. Raises if entity_ids isn't an Array or if no block is given.
 */
static mrb_value m_each_row(mrb_state *mrb, mrb_value self)
    __attribute__((force_align_arg_pointer));
static mrb_value m_each_row(mrb_state *mrb, mrb_value self) {
    (void)self;

    mrb_value entity_ids_v, stores_v, block_v;
    /* Format "oA&": Object (entity_ids), Array (stores), & (block).
     * mrb_get_args with "&" captures the block as a Proc; if no block was
     * passed, it raises ArgumentError, which is the behavior we want
     * (each_row is a yield-only API). */
    drb->mrb_get_args(mrb, "oA&", &entity_ids_v, &stores_v, &block_v);

    if (!mrb_array_p(entity_ids_v)) {
        drb->mrb_raise(mrb, drb->drb_getruntime_error(mrb),
                       "drecs: each_row entity_ids must be an Array");
        return mrb_nil_value();
    }

    mrb_int count = RARRAY_LEN(entity_ids_v);
    if (count <= 0) return mrb_nil_value();

    mrb_int num_stores = RARRAY_LEN(stores_v);

    /* Pre-fetch per-store raw pointers. Saves one RARRAY_PTR per store
     * per row in the hot loop. */
    mrb_value **store_ptrs = NULL;
    if (num_stores > 0) {
        store_ptrs = (mrb_value **)drb->mrb_malloc(mrb,
                                                   sizeof(mrb_value *) * (size_t)num_stores);
        mrb_value *store_items = RARRAY_PTR(stores_v);
        for (mrb_int s = 0; s < num_stores; s++) {
            store_ptrs[s] = RARRAY_PTR(store_items[s]);
        }
    }

    mrb_value *eid_items = RARRAY_PTR(entity_ids_v);

    /* Per-row block dispatch. Specialize on num_stores so the 0-4 cases
     * never allocate an args array. */
    switch (num_stores) {
    case 0:
        for (mrb_int i = 0; i < count; i++) {
            mrb_value args[1];
            args[0] = eid_items[i];
            drb->mrb_yield_argv(mrb, block_v, 1, args);
        }
        break;
    case 1: {
        mrb_value *s0 = store_ptrs[0];
        for (mrb_int i = 0; i < count; i++) {
            mrb_value args[2];
            args[0] = eid_items[i];
            args[1] = s0[i];
            drb->mrb_yield_argv(mrb, block_v, 2, args);
        }
        break;
    }
    case 2: {
        mrb_value *s0 = store_ptrs[0];
        mrb_value *s1 = store_ptrs[1];
        for (mrb_int i = 0; i < count; i++) {
            mrb_value args[3];
            args[0] = eid_items[i];
            args[1] = s0[i];
            args[2] = s1[i];
            drb->mrb_yield_argv(mrb, block_v, 3, args);
        }
        break;
    }
    case 3: {
        mrb_value *s0 = store_ptrs[0];
        mrb_value *s1 = store_ptrs[1];
        mrb_value *s2 = store_ptrs[2];
        for (mrb_int i = 0; i < count; i++) {
            mrb_value args[4];
            args[0] = eid_items[i];
            args[1] = s0[i];
            args[2] = s1[i];
            args[3] = s2[i];
            drb->mrb_yield_argv(mrb, block_v, 4, args);
        }
        break;
    }
    case 4: {
        mrb_value *s0 = store_ptrs[0];
        mrb_value *s1 = store_ptrs[1];
        mrb_value *s2 = store_ptrs[2];
        mrb_value *s3 = store_ptrs[3];
        for (mrb_int i = 0; i < count; i++) {
            mrb_value args[5];
            args[0] = eid_items[i];
            args[1] = s0[i];
            args[2] = s1[i];
            args[3] = s2[i];
            args[4] = s3[i];
            drb->mrb_yield_argv(mrb, block_v, 5, args);
        }
        break;
    }
    default: {
        /* 5+ stores: pre-allocate the args array once, reuse for every row. */
        mrb_value *args = (mrb_value *)drb->mrb_malloc(
            mrb, sizeof(mrb_value) * (size_t)(num_stores + 1));
        for (mrb_int i = 0; i < count; i++) {
            args[0] = eid_items[i];
            for (mrb_int s = 0; s < num_stores; s++) {
                args[s + 1] = store_ptrs[s][i];
            }
            drb->mrb_yield_argv(mrb, block_v, num_stores + 1, args);
        }
        drb->mrb_free(mrb, args);
        break;
    }
    }

    if (store_ptrs) drb->mrb_free(mrb, store_ptrs);

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
    drb->mrb_define_module_function(mrb, parallel, "run_kernel_native",
                                    m_run_kernel_native, MRB_ARGS_REQ(8));
    drb->mrb_define_module_function(mrb, parallel, "each_row",
                                    m_each_row, MRB_ARGS_ANY());

    drb->mrb_define_const(mrb, parallel, "AVAILABLE", mrb_true_value());
}
