# nbody_gravity sample - native C kernel running O(N²) gravity sim across SDL3 threads.
#
# This is the canonical "threading wins" demo for drecs-native. Each
# particle sums gravitational attraction from every other particle
# per frame (O(N²)), so per-row work scales with N. At N=1500 that's
# ~22 million flops per frame, which is enough work for the native
# kernel to amortize SDL thread create/join overhead and show real
# speedup vs single-threaded.
#
# Run with:
#   dragonruby.exe drecs --sample nbody_gravity
#
# Before running, build the kernel with:
#   samples\nbody_gravity\build.bat
#
# Controls:
#   + / =   add 100 particles
#   -       remove 100 particles (last-spawned first)
#   1 / 2 / 4 / 8   set :nbody_step thread count
#   R       toggle Ruby fallback vs native path
#
# Watch the VISIBLE fps line. At N=1500 with 8 threads you should see
# 7-8× the fps of the Ruby fallback. This is the demo that actually
# shows why you'd use drecs-native + threads.

RESOLUTION = { w: 1280, h: 720 }

PARTICLE_COUNT = 1500
DEFAULT_THREADS = 4

# Gravitational constant. MUST match the #define G in app/nbody_kernel.c.
# The real G (6.674e-11) is useless at game scale; this is tuned for
# visible orbital motion at N=1500 in a 1280x720 space.
G = 0.5

# ECS component classes. Drecs.component(:x, :y) stores fields as @-ivars
# (unlike Struct, whose fields live in an internal C array), which is what the
# native kernel's mrb_iv_get path reads directly.
Position = Drecs.component(:x, :y)
Velocity = Drecs.component(:x, :y)
Color    = Drecs.component(:r, :g, :b, :a)

GameTime   = Struct.new(:elapsed, :delta)
GameConfig = Struct.new(:particle_count, :threads, :use_native, :g)

# ParticleDot is a persistent renderable view of one particle. We
# dynamically push a new instance into `args.outputs.static_sprites`
# when a particle is spawned and delete it when the particle is
# removed — keeping the renderer's per-frame work exactly equal to
# the live particle count, never iterating dead pool slots.
#
# Compare to `args.outputs.solids << { x:, y:, ... }` which allocates a
# Hash per primitive per frame — at N=20000 that's 20000 GC-tracked
# allocations every tick. Or to pre-allocating a fixed pool — which
# forces DR to iterate the full pool even if only a fraction is
# active, and burns memory you never use.
#
# Pattern adapted from `samples/99_genre_simulation/sand_simulation/`,
# which handles ~50k elements at 60fps using the same approach.
class ParticleDot
  attr_sprite

  def initialize
    @path = :solid
    @w    = 3
    @h    = 3
    @r    = 200
    @g    = 200
    @b    = 200
    @a    = 255
    @x    = 0
    @y    = 0
  end

  # draw_override is the older but possibly faster path (used by
  # samples/99_genre_simulation/sand_simulation for ~50k elements
  # at 60fps). Compare perf against attr_sprite alone.
  def draw_override(ffi)
    ffi.draw_sprite_ivar self
  end
end

# ---- Logging ---------------------------------------------------------------

LOG_PATH = 'nbody_log.txt'

def flog(msg)
  $stdout.puts msg rescue nil
  File.open(LOG_PATH, 'a') { |f| f.puts msg } rescue nil
end

# ---- Spawning --------------------------------------------------------------

# Spawn `n` particles in a disk around the screen center with tangential
# velocities. Tangential initial velocity gives them angular momentum so
# they orbit instead of just collapsing to the center.
#
# Each spawned particle gets a matching ParticleDot pushed into
# `args.outputs.static_sprites` and tracked in
# `args.state[:renderables]` keyed by entity_id, so the renderer's
# per-frame work is exactly proportional to the live particle count.
def spawn_particles(world, n, static_sprites)
  return if n <= 0
  cx = RESOLUTION[:w] / 2.0
  cy = RESOLUTION[:h] / 2.0
  i = 0
  while i < n
    # Uniform in a disk: sqrt(rand) gives uniform area distribution.
    angle = rand * Math::PI * 2.0
    r = Math.sqrt(rand) * 280.0
    px = cx + Math.cos(angle) * r
    py = cy + Math.sin(angle) * r

    # Tangential velocity (perpendicular to radial direction) gives
    # the swarm angular momentum so they orbit instead of falling in.
    tang = angle + Math::PI / 2.0
    speed = 0.4 + rand * 1.2
    vx = Math.cos(tang) * speed
    vy = Math.sin(tang) * speed

    # Color: random hue, full saturation. Helps visually distinguish
    # particles as they orbit.
    hue = rand
    r8 = (Math.sin(hue * 6.2832)         * 127.0 + 128.0).to_i
    g8 = (Math.sin(hue * 6.2832 + 2.094) * 127.0 + 128.0).to_i
    b8 = (Math.sin(hue * 6.2832 + 4.188) * 127.0 + 128.0).to_i

    color = Color.new(r8, g8, b8, 255)
    eid = world.spawn(
      Position.new(px, py),
      Velocity.new(vx, vy),
      color
    )

    # Persistent renderable. Same instance across frames; DR reads
    # its iVars via the sprite pipeline. Zero per-frame allocation.
    r = ParticleDot.new
    r.x = px - 1.5
    r.y = py - 1.5
    r.r = color.r
    r.g = color.g
    r.b = color.b
    args.state[:renderables][eid] = r
    static_sprites << r

    i += 1
  end
end

# Find a particle that has all three components (the highest-id one)
# and remove it. Used for the `-` keypress. Also removes the matching
# ParticleDot from args.outputs.static_sprites so the renderer's
# iteration count drops with the live particle count.
def remove_last_particle(world, static_sprites)
  ids = world.ids(Position)
  return false if ids.empty?
  victim = ids.last
  world.remove_component(victim, Position)
  world.remove_component(victim, Velocity)
  world.remove_component(victim, Color)
  r = args.state[:renderables].delete(victim)
  static_sprites.delete(r) if r
  true
end

# ---- Native-system plumbing ------------------------------------------------

def setup_native_systems(world, threads)
  world.register_native_system(
    :nbody_step,
    module_name: "NBodyKernel",
    kernel:      :nbody_step,
    reads:       [[Position, :x], [Position, :y],
                  [Velocity, :x], [Velocity, :y]],
    writes:      [[Position, :x], [Position, :y],
                  [Velocity, :x], [Velocity, :y]],
    threads:     threads,
  )
end

# ---- Boot ------------------------------------------------------------------

def boot(args)
  args.state[:phase] ||= :init
  return if args.state[:phase] != :init

  flog "[nbody] boot init"

  parallel_ok = false
  kernel_ok   = false

  begin
    DR.dlopen "drecs_parallel"
    Drecs::Parallel.load
    parallel_ok = Drecs::Parallel.available?
    flog "[nbody] drecs_parallel loaded, available?=#{parallel_ok}"
  rescue => e
    flog "[nbody] drecs_parallel FAILED: #{e.message}"
  end

  begin
    DR.dlopen "nbody_kernel"
    flog "[nbody] nbody_kernel loaded; NBodyKernel?=#{Object.const_defined?(:NBodyKernel)}"
    kernel_ok = Object.const_defined?(:NBodyKernel)
  rescue => e
    flog "[nbody] nbody_kernel FAILED: #{e.message}"
  end

  args.state[:parallel_ok] = parallel_ok && kernel_ok

  if args.state[:parallel_ok]
    world = Drecs::World.new
    setup_native_systems(world, DEFAULT_THREADS)

    # Initialize the entity_id -> renderable map. spawn_particles
    # below pushes one ParticleDot into args.outputs.static_sprites
    # per spawned entity and stores it in this hash keyed by entity_id.
    args.state[:renderables] = {}

    spawn_particles(world, PARTICLE_COUNT, args.outputs.static_sprites)

    world.insert_resource(GameTime.new(0.0, 0.016))
    world.insert_resource(GameConfig.new(PARTICLE_COUNT, DEFAULT_THREADS, true, G))
    args.state[:world] = world

    flog "[nbody] spawned #{PARTICLE_COUNT} particles, native system registered"
  else
    flog "[nbody] native unavailable, will use ruby fallback if R toggled"
  end

  args.state[:phase] = :running
end

# ---- Tick ------------------------------------------------------------------

def tick(args)
  boot(args) if args.state[:phase] == :init

  world = args.state[:world]
  return $gtk.exit unless world

  config = world.resource(GameConfig)
  time   = world.resource(GameTime)
  time.elapsed += time.delta

  # --- Input: scaling particles ---
  if args.inputs.keyboard.key_down.plus || args.inputs.keyboard.key_down.equal
    spawn_particles(world, 100, args.outputs.static_sprites)
    config.particle_count += 100
    flog "[nbody] +100 particles -> #{config.particle_count}"
  end

  if args.inputs.keyboard.key_down.minus
    removed = 0
    while removed < 100 && remove_last_particle(world, args.outputs.static_sprites)
      removed += 1
    end
    config.particle_count = [config.particle_count - removed, 0].max
    flog "[nbody] -#{removed} particles -> #{config.particle_count}"
  end

  # --- Input: thread count ---
  if args.inputs.keyboard.key_down.one
    world.native_systems[:nbody_step][:threads] = 1
    config.threads = 1
  end
  if args.inputs.keyboard.key_down.two
    world.native_systems[:nbody_step][:threads] = 2
    config.threads = 2
  end
  if args.inputs.keyboard.key_down.three
    world.native_systems[:nbody_step][:threads] = 4
    config.threads = 4
  end
  if args.inputs.keyboard.key_down.four
    world.native_systems[:nbody_step][:threads] = 8
    config.threads = 8
  end

  # --- Input: toggle mode ---
  if args.inputs.keyboard.key_down.r
    config.use_native = !config.use_native
    flog "[nbody] mode -> #{config.use_native ? 'native' : 'ruby'}"
  end

  # --- Simulation ---
  if config.use_native && args.state[:parallel_ok]
    world.run_native_system(:nbody_step, dt: time.delta)
  else
    ruby_nbody_step(world, time.delta)
  end

  # --- Render ---
  # Sync each live drecs entity's Position/Color into its matching
  # ParticleDot. The renderable pool is keyed by entity_id (a Hash)
  # because drecs archetype swaps on destroy change row indices but
  # entity_ids are stable.
  #
  # Previously this used Drecs::Parallel.blit_renderables (C-side sync)
  # for a ~10x speedup. That helper has been removed from the runtime;
  # write a native kernel if you need that path back. The plain Ruby
  # loop below caps out around 5k particles; for higher counts, define
  # a DRECS_KERNEL in your own extension that walks the struct stores
  # and calls ParticleDot's attr_sprite setters in C.
  renderables = args.state[:renderables]
  world.each_chunk(Position, Color) do |entity_ids, positions, colors|
    positions.length.times do |i|
      eid = entity_ids[i]
      ren = renderables[eid]
      next unless ren
      pos = positions[i]
      col = colors[i]
      ren.x = pos.x - 1.5
      ren.y = pos.y - 1.5
      ren.r = col.r
      ren.g = col.g
      ren.b = col.b
      ren.a = col.a
    end
  end

  # --- Debug overlay ---
  # As with the boids sample: VISIBLE fps is what you see, sim is
  # what's calculated per frame, render is what's drawn. Don't
  # mistake sim fps for the displayed frame rate.
  args.outputs.debug << "VISIBLE fps: #{args.gtk.current_framerate.round(1)}"
  args.outputs.debug << "  sim:    #{args.gtk.current_framerate_calc.round(1)}"
  args.outputs.debug << "  render: #{args.gtk.current_framerate_render.round(1)}"
  args.outputs.debug << "particles: #{config.particle_count}"
  args.outputs.debug << "mode: #{config.use_native && args.state[:parallel_ok] ? 'native' : 'ruby'}"
  args.outputs.debug << "step threads: #{config.threads}"
  args.outputs.debug << "controls: +/- particles  1/2/4/8 threads  R ruby/native"

  # One-shot FPS log at the 3-second mark so headless runs capture a
  # steady-state number without the GUI overlay.
  args.state[:tick_count] = (args.state[:tick_count] || 0) + 1
  if args.state[:tick_count] == 180 && args.state[:parallel_ok]
    flog "[nbody] t=3s  visible_fps=#{args.gtk.current_framerate.round(1)} " \
         "sim=#{args.gtk.current_framerate_calc.round(1)} " \
         "particles=#{config.particle_count} threads=#{config.threads} mode=native"
  end
end

# ---- Ruby fallback (mirrors C kernel 1:1 for A/B comparison) -------------
# Same O(N²) force loop, same softening, same Euler integration, same
# wrap. Used to demonstrate the "C beats Ruby" win at this workload —
# at N=1500 the Ruby path becomes a slideshow while native at 8
# threads hits a comfortable 60 fps.

SOFTENING_R = 0.001
SOFTENING_SQ_R = SOFTENING_R * SOFTENING_R

def ruby_nbody_step(world, dt)
  world.each_chunk(Position, Velocity) do |_entity_ids, positions, velocities|
    next if positions.empty?
    count = positions.length

    # Compute accelerations. Single-threaded Ruby — this is the slow
    # path. At N=1500 it takes seconds per frame in pure mruby; the C
    # kernel takes ~1.5ms at 8 threads. That's where the demo lives.
    #
    # Use `count.times do |i| ... count.times do |j| ...` rather than
    # `while` loops with manual `i += 1` / `j += 1`. The reason: `next`
    # inside a `while` loop jumps to the condition check WITHOUT
    # running the post-body increment, so `next if j == i` would skip
    # the `j += 1` and hang. Iterator-based loops advance automatically
    # on `next`, so this version is safe.
    accelerations = Array.new(count * 2, 0.0)
    count.times do |i|
      xi = positions[i].x
      yi = positions[i].y
      fx = 0.0
      fy = 0.0
      count.times do |j|
        next if j == i
        dx = positions[j].x - xi
        dy = positions[j].y - yi
        r2 = dx * dx + dy * dy + SOFTENING_SQ_R
        inv_r3 = 1.0 / (r2 * Math.sqrt(r2))
        fx += dx * inv_r3
        fy += dy * inv_r3
      end
      accelerations[i * 2]     = G * fx
      accelerations[i * 2 + 1] = G * fy
    end

    # Integrate.
    count.times do |i|
      ax = accelerations[i * 2]
      ay = accelerations[i * 2 + 1]
      vel = velocities[i]
      vel.x += ax * dt
      vel.y += ay * dt
      pos = positions[i]
      new_px = pos.x + vel.x * dt
      new_py = pos.y + vel.y * dt

      if new_px < 0.0
        new_px += RESOLUTION[:w]
      elsif new_px >= RESOLUTION[:w]
        new_px -= RESOLUTION[:w]
      end
      if new_py < 0.0
        new_py += RESOLUTION[:h]
      elsif new_py >= RESOLUTION[:h]
        new_py -= RESOLUTION[:h]
      end

      pos.x = new_px
      pos.y = new_py
    end
  end
end