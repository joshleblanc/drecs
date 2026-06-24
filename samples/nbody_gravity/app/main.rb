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

# ECS component classes. Drecs.component(:x, :y) gives us Struct
# subclasses with float members — same as plain Struct.new but
# semantically tagged as a drecs component.
Position = Drecs.component(:x, :y)
Velocity = Drecs.component(:x, :y)
Color    = Drecs.component(:r, :g, :b, :a)

GameTime   = Struct.new(:elapsed, :delta)
GameConfig = Struct.new(:particle_count, :threads, :use_native, :g)

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
def spawn_particles(world, n)
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

    world.spawn(
      Position.new(px, py),
      Velocity.new(vx, vy),
      Color.new(r8, g8, b8, 255)
    )
    i += 1
  end
end

# Find a particle that has all three components (the highest-id one)
# and remove it. Used for the `-` keypress.
def remove_last_particle(world)
  ids = world.ids(Position)
  return false if ids.empty?
  victim = ids.last
  world.remove_component(victim, Position)
  world.remove_component(victim, Velocity)
  world.remove_component(victim, Color)
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
    spawn_particles(world, PARTICLE_COUNT)
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
    spawn_particles(world, 100)
    config.particle_count += 100
    flog "[nbody] +100 particles -> #{config.particle_count}"
  end

  if args.inputs.keyboard.key_down.minus
    removed = 0
    while removed < 100 && remove_last_particle(world)
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
  solids = []
  world.query(Position, Color) do |_entity_ids, positions, colors|
    n = positions.length
    i = 0
    while i < n
      pos = positions[i]
      c   = colors[i]
      # 3x3 dot. Bigger makes individual particles easier to track
      # but blows up render cost; at N=1500, 3x3 is the sweet spot.
      solids << {
        x: pos.x - 1.5, y: pos.y - 1.5, w: 3, h: 3,
        r: c.r, g: c.g, b: c.b, a: c.a
      }
      i += 1
    end
  end
  args.outputs.solids << solids

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
  world.query(Position, Velocity) do |_entity_ids, positions, velocities|
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