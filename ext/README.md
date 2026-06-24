# drecs Parallel Runtime + Native Systems

This directory provides two things:

1. **`drecs_parallel.c`** - the drecs parallel runtime, compiled to
   `drecs_parallel.dll` / `.so` / `.dylib` and loaded via
   `DR.dlopen "drecs_parallel"`. It exposes a generic kernel runner that
   fans work out across SDL3 threads.
2. **`drecs_kernel.h`** - the public header you include in your *own*
   DragonRuby C extension to author native ECS systems.

The drecs Ruby side never tries to run user kernels itself; it extracts
component data into SoA `double[]` arrays, calls `Drecs::Parallel.run_kernel`,
and writes results back into your component structs.

## Why a separate user extension?

mruby is single-threaded. Worker threads cannot touch any `mrb_*` API.
The only thing they can safely operate on is plain C memory. So:

- The drecs runtime extracts components on the main thread (Ruby side).
- Your kernel runs in C on `double*` buffers across N threads.
- The drecs runtime writes back on the main thread and bumps change ticks.

Your kernel is a pure C function with the signature
`void kernel(const drecs_kernel_ctx*)`. You never deal with threads,
mruby, SDL, or DragonRuby's API. See `drecs_kernel.h` for the ctx layout.

## Build the runtime

From `drecs\ext\`:

```bat
build.bat
```

Or manually:

```bash
gcc -shared -O2 -I../../dragonruby/include -o drecs_parallel.dll drecs_parallel.c
```

Place the resulting `drecs_parallel.dll`/`.so`/`.dylib` next to your
DragonRuby project so `DR.dlopen "drecs_parallel"` finds it (typically
under `mygame/native/<platform>/`).

## Authoring a native system

Minimal user extension `my_systems.c`:

```c
#include "drecs_kernel.h"

DRECS_DEFINE_STORAGE;

DRECS_KERNEL(integrate_motion) {
    const double *px = ctx->in[0], *py = ctx->in[1];
    const double *vx = ctx->in[2], *vy = ctx->in[3];
    double *opx = ctx->out[0], *opy = ctx->out[1];
    double dt = ctx->dt;
    for (int i = ctx->start; i < ctx->end; i++) {
        opx[i] = px[i] + vx[i] * dt;
        opy[i] = py[i] + vy[i] * dt;
    }
}
DRECS_KERNEL_EXPORT(integrate_motion)

DRB_FFI_EXPORT
void drb_register_c_extensions_with_api(mrb_state *mrb, struct drb_api_t *api) {
    DRECS_INIT(api);
    struct RClass *mod = api->mrb_define_module(mrb, "MySystems");
    DRECS_KERNEL_REGISTER(mrb, mod, integrate_motion);
}
```

Build it like any DragonRuby C extension and place it at
`mygame/native/<platform>/my_systems.<ext>`. A working example lives in
`samples/native_systems/`.

Then on the Ruby side:

```ruby
DR.dlopen "drecs_parallel"
DR.dlopen "my_systems"
Drecs::Parallel.load

world.register_native_system(
  :integrate,
  module_name: "MySystems",
  kernel:      :integrate_motion,
  reads:       [[Position, :x], [Position, :y], [Velocity, :x], [Velocity, :y]],
  writes:      [[Position, :x], [Position, :y]],
  threads:     4,
)

# Per frame:
world.run_native_system(:integrate, dt: 1.0 / 60.0)
```

## Hard rules inside a kernel

- Do **not** call any `mrb_*` function. Workers run concurrently; mruby is not thread-safe.
- Do **not** allocate Ruby objects, raise, or call back into Ruby.
- Do **not** write outside `[ctx->start, ctx->end)` - other threads own those rows.
- Do **not** mutate `ctx->in[*]`. They are inputs.
- libc, SDL primitives, and your own thread-local state are fine.

## When parallelism actually pays off

The runtime extracts component data into `double` columns each call.
That marshal/writeback is O(rows x members). You get a speedup when:

- The kernel itself is non-trivial (force accumulation, neighbor search,
  many-op physics, etc.), and
- Entity counts are at least a few hundred.

Trivial kernels over small archetypes will be slower than plain Ruby
because of marshal overhead. Measure before committing.

## API surface

Ruby side:

| Method | Description |
|--------|-------------|
| `Drecs::Parallel.load` | Mark the runtime as loaded after `DR.dlopen`. |
| `Drecs::Parallel.available?` | Whether the runtime is ready to run kernels. |
| `Drecs::Parallel.hardware_threads` | Logical CPU core count. |
| `Drecs::Parallel.run_kernel(fn_ptr, in_arrays, out_arrays, count, dt, threads)` | Low-level: fan a kernel out across threads. Most users go through `World#run_native_system`. |
| `World#register_native_system(name, module_name:, kernel:, reads:, writes:, with:, without:, any:, threads:)` | Register a kernel as a named system. |
| `World#run_native_system(name, dt:)` | Run a registered native system across all matching archetypes. |

C side (in `drecs_kernel.h`):

| Macro | Purpose |
|-------|---------|
| `DRECS_DEFINE_STORAGE` | Place once at file scope; provides storage for the drb api pointer. |
| `DRECS_INIT(api)` | Call from your `drb_register_c_extensions_with_api`. |
| `DRECS_KERNEL(name)` | Declare a kernel function. |
| `DRECS_KERNEL_EXPORT(name)` | Generate the Ruby-callable getter for a kernel. |
| `DRECS_KERNEL_REGISTER(mrb, mod, name)` | Wire the kernel getter into an mruby module. |
