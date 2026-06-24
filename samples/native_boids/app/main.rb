# native_boids sample - native C kernel running boids across SDL3 threads.
#
# Two registered native systems fan work across real worker threads:
#   :boids_grid  - 1 thread,  builds the spatial grid into static scratch
#   :boids_step  - N threads,  parallel boids update reading that scratch
#
# Run with:
#   dragonruby.exe drecs --sample native_boids
#
# Before running, build the kernel with:
#   samples\native_boids\build.bat
#
# Controls (live):
#   + / =   add 1000 boids
#   -       remove 1000 boids (if you've spawned enough)
#   1 / 2 / 3 / 4   set :boids_step thread count to 1 / 2 / 4 / 8
#   R       toggle Ruby fallback vs native path
#
# The simulation constants (NEIGHBOUR_RANGE, weights, etc.) MUST match
# the values hardcoded in app/boids_kernel.c. If you change them here,
# mirror them there.

RESOLUTION = { w: 1280, h: 720 }

BOIDS_COUNT     = 5_000    # match the original boids baseline; press + to scale up
DEFAULT_THREADS = 2        # safe default — see "thread count sweet spot" in README

SEPARATION_WEIGHT = 20
ALIGNMENT_WEIGHT  = 1.0
COHESION_WEIGHT   = 1.0
NEIGHBOUR_RANGE   = 10
MIN_VELOCITY      = 2
MAX_VELOCITY      = 5

# ECS component classes. Using Drecs.component(:x, :y) gives us Struct
# subclasses with float members.
Position = Drecs.component(:x, :y)
Velocity = Drecs.component(:x, :y)
Size     = Drecs.component(:w, :h)
Color    = Drecs.component(:r, :g, :b, :a)

GameTime   = Struct.new(:elapsed, :delta)
GameConfig = Struct.new(:boids_count, :threads, :use_native)

# ---- Logging ---------------------------------------------------------------

LOG_PATH = 'native_boids_log.txt'

def flog(msg)
  $stdout.puts msg rescue nil
  begin
    File.open(LOG_PATH, 'a') { |f| f.puts msg }
  rescue
  end
end

# ---- Spawning --------------------------------------------------------------

def spawn_boids(world, n)
  return if n <= 0
  i = 0
  while i < n
    pos = Position.new(rand * RESOLUTION[:w], rand * RESOLUTION[:h])
    # Random normalized direction with speed in [MIN_VELOCITY, MAX_VELOCITY].
    dx = rand - 0.5
    dy = rand - 0.5
    m  = Math.sqrt(dx * dx + dy * dy)
    if m.zero?
      dx = 1.0; dy = 0.0; m = 1.0
    end
    dx /= m; dy /= m
    speed = MIN_VELOCITY + rand * (MAX_VELOCITY - MIN_VELOCITY)
    vel   = Velocity.new(dx * speed, dy * speed)
    size  = Size.new(5, 5)
    color = Color.new(rand(255).to_i, rand(255).to_i, rand(255).to_i, 255)
    world.spawn(pos, vel, size, color)
    i += 1
  end
end

# Find the highest-id entity that has all four boid components, so we can
# remove it cleanly. Removal pops from the archetype's swap-and-pop store,
# so removing the last-spawned keeps the simulation visually stable.
def remove_last_boid(world)
  ids = world.ids(Position, Velocity, Size, Color)
  return false if ids.empty?
  victim = ids.last
  # Remove one component to detach it from the Position+Velocity archetype;
  # the simplest correct approach is to detach from each component class.
  world.remove_component(victim, Position)
  world.remove_component(victim, Velocity)
  world.remove_component(victim, Size)
  world.remove_component(victim, Color)
  true
end

# ---- Native-system plumbing ------------------------------------------------

def setup_native_systems(world, threads)
  world.register_native_system(
    :boids_grid,
    module_name: "BoidsKernel",
    kernel:      :boids_build_grid,
    reads:       [[Position, :x], [Position, :y]],
    writes:      [],
    threads:     1,
  )
  world.register_native_system(
    :boids_step,
    module_name: "BoidsKernel",
    kernel:      :boids_step,
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

  flog "[native_boids] boot init"

  parallel_ok = false
  kernel_ok   = false

  begin
    DR.dlopen "drecs_parallel"
    Drecs::Parallel.load
    parallel_ok = Drecs::Parallel.available?
    flog "[native_boids] drecs_parallel loaded, available?=#{parallel_ok}"
  rescue => e
    flog "[native_boids] drecs_parallel FAILED: #{e.message}"
  end

  begin
    DR.dlopen "boids_kernel"
    flog "[native_boids] boids_kernel loaded; BoidsKernel?=#{Object.const_defined?(:BoidsKernel)}"
    kernel_ok = Object.const_defined?(:BoidsKernel)
  rescue => e
    flog "[native_boids] boids_kernel FAILED: #{e.message}"
  end

  args.state[:parallel_ok] = parallel_ok && kernel_ok

  if args.state[:parallel_ok]
    world = Drecs::World.new
    setup_native_systems(world, DEFAULT_THREADS)
    spawn_boids(world, BOIDS_COUNT)
    world.insert_resource(GameTime.new(0.0, 0.016))
    world.insert_resource(GameConfig.new(BOIDS_COUNT, DEFAULT_THREADS, true))
    args.state[:world] = world
    flog "[native_boids] spawned #{BOIDS_COUNT} boids, native systems registered"
  else
    flog "[native_boids] native unavailable, will use Ruby fallback if R toggled"
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

  # --- Input: scaling boids ---
  if args.inputs.keyboard.key_down.plus || args.inputs.keyboard.key_down.equal
    spawn_boids(world, 1000)
    config.boids_count += 1000
    flog "[native_boids] +1000 boids -> #{config.boids_count}"
  end

  if args.inputs.keyboard.key_down.minus
    removed = 0
    while removed < 1000 && remove_last_boid(world)
      removed += 1
    end
    config.boids_count = [config.boids_count - removed, 0].max
    flog "[native_boids] -#{removed} boids -> #{config.boids_count}"
  end

  # --- Input: thread count ---
  # Linear mapping — the labels match what you get. 5 is the "advanced"
  # key that pushes past logical-core count; useful only at heavy
  # workloads (>= ~15k boids) where the kernel itself is the bottleneck.
  if args.inputs.keyboard.key_down.one
    world.native_systems[:boids_step][:threads] = 1
    config.threads = 1
  end
  if args.inputs.keyboard.key_down.two
    world.native_systems[:boids_step][:threads] = 2
    config.threads = 2
  end
  if args.inputs.keyboard.key_down.three
    world.native_systems[:boids_step][:threads] = 3
    config.threads = 3
  end
  if args.inputs.keyboard.key_down.four
    world.native_systems[:boids_step][:threads] = 4
    config.threads = 4
  end
  if args.inputs.keyboard.key_down.five
    world.native_systems[:boids_step][:threads] = 8
    config.threads = 8
  end

  # --- Input: toggle mode ---
  if args.inputs.keyboard.key_down.r
    config.use_native = !config.use_native
    flog "[native_boids] mode -> #{config.use_native ? 'native' : 'ruby'}"
  end

  # --- Simulation ---
  if config.use_native && args.state[:parallel_ok]
    world.run_native_system(:boids_grid, dt: time.delta)
    world.run_native_system(:boids_step, dt: time.delta)
  else
    ruby_boids_step(world, time.delta, config.boids_count)
  end

  # --- Render ---
  solids = []
  world.query(Position, Size, Color) do |_entity_ids, positions, sizes, colors|
    n = positions.length
    i = 0
    while i < n
      pos = positions[i]
      s   = sizes[i]
      c   = colors[i]
      solids << {
        x: pos.x, y: pos.y, w: s.w, h: s.h,
        r: c.r, g: c.g, b: c.b, a: c.a
      }
      i += 1
    end
  end
  args.outputs.solids << solids

  # --- Debug overlay ---
  # Note: `current_framerate` (the number you actually see) is the
  # slower of sim vs render. `current_framerate_calc` is sim-only and
  # hits 60 even when the rendered output is stuttering — don't be
  # fooled by it. We label them clearly so the right one is obvious.
  visible_fps = args.gtk.current_framerate
  calc_fps    = args.gtk.current_framerate_calc
  render_fps  = args.gtk.current_framerate_render
  args.outputs.debug << "  fps: #{visible_fps.round(1)}"
  args.outputs.debug << "  sim:    #{calc_fps.round(1)}"
  args.outputs.debug << "  render: #{render_fps.round(1)}"
  args.outputs.debug << "boids:  #{config.boids_count}"
  args.outputs.debug << "mode:   #{config.use_native && args.state[:parallel_ok] ? 'native' : 'ruby'}"
  args.outputs.debug << "step threads: #{config.threads}"
  args.outputs.debug << "controls: +/- boids  1..5 threads  R ruby/native"
  if config.threads >= 5
    args.outputs.debug << "  note: threads>~cores only helps at heavy workloads"
  end

  # --- One-shot FPS log at the 3-second mark so headless runs / CI can
  #     capture a steady-state number without needing the GUI overlay. ---
  args.state[:tick_count] = (args.state[:tick_count] || 0) + 1
  if args.state[:tick_count] == 180 && args.state[:parallel_ok]
    flog "[native_boids] t=3s  fps=#{args.gtk.current_framerate.round(1)} " \
         "calc=#{args.gtk.current_framerate_calc.round(1)} " \
         "boids=#{config.boids_count} threads=#{config.threads} mode=native"
  end
end

# ---- Ruby fallback (mirrors the C kernel's algorithm 1:1 for parity) ------
# Same separation / cohesion / alignment math, same grid, same wrap, same
# velocity decay. Useful for A/B toggling.

SEPARATION_WEIGHT_R = SEPARATION_WEIGHT
ALIGNMENT_WEIGHT_R  = ALIGNMENT_WEIGHT
COHESION_WEIGHT_R   = COHESION_WEIGHT
ALIGNMENT_DIVISOR_R = 4
COHESION_DIVISOR_R  = 100
NEIGHBOUR_RANGE_SQ_R = NEIGHBOUR_RANGE * NEIGHBOUR_RANGE
MAX_NEIGHBOURS_R     = 2

def ruby_boids_step(world, dt, _expected_count)
  # Query both Position and Velocity in one call so the iteration aligns
  # by row index. drecs's query yields (entity_ids, *stores) per matching
  # archetype; we ask for both classes together so positions[i] and
  # velocities[i] line up.
  #
  # NOTE: the previous version made two separate queries and tried to
  # destructure a single-component query as two args, leaving the second
  # as nil. nil[i] in the inner loop blew up the tick. This version
  # queries both at once and reads `.x` / `.y` off the resulting structs.
  world.query(Position, Velocity) do |_entity_ids, positions, velocities|
    next if positions.empty?

    # Build spatial grid of boid indices keyed by cell.
    grid = Array.new(128) { Array.new(72) { [] } }
    positions.each_with_index do |pos, i|
      cx = (pos.x.to_i / 10).clamp(0, 127)
      cy = (pos.y.to_i / 10).clamp(0, 71)
      grid[cx][cy] << i
    end

    scale = dt * 100.0
    positions.each_with_index do |pos, i|
      vel = velocities[i]
      cx  = (pos.x.to_i / 10).clamp(0, 127)
      cy  = (pos.y.to_i / 10).clamp(0, 71)

      coh_x = 0.0; coh_y = 0.0
      sep_x = 0.0; sep_y = 0.0
      ali_x = 0.0; ali_y = 0.0
      n = 0

      (-1..1).each do |dx|
        (-1..1).each do |dy|
          ncx = cx + dx; ncy = cy + dy
          next if ncx < 0 || ncx >= 128 || ncy < 0 || ncy >= 72
          break if n >= MAX_NEIGHBOURS_R
          cell = grid[ncx][ncy]
          cell.each do |j|
            next if j == i
            other_pos = positions[j]
            other_vel = velocities[j]
            dux = pos.x - other_pos.x
            duy = pos.y - other_pos.y
            d2 = dux * dux + duy * duy
            if d2 < NEIGHBOUR_RANGE_SQ_R && d2 > 0
              inv = 1.0 / d2
              sep_x += dux * inv
              sep_y += duy * inv
            end
            coh_x += other_pos.x
            coh_y += other_pos.y
            ali_x += other_vel.x
            ali_y += other_vel.y
            n += 1
            break if n >= MAX_NEIGHBOURS_R
          end
        end
      end

      if n > 0
        coh_x = (coh_x / n - pos.x) / COHESION_DIVISOR_R * COHESION_WEIGHT_R
        coh_y = (coh_y / n - pos.y) / COHESION_DIVISOR_R * COHESION_WEIGHT_R
        sep_x *= SEPARATION_WEIGHT_R
        sep_y *= SEPARATION_WEIGHT_R
        ali_x = (ali_x / n - vel.x) / ALIGNMENT_DIVISOR_R * ALIGNMENT_WEIGHT_R
        ali_y = (ali_y / n - vel.y) / ALIGNMENT_DIVISOR_R * ALIGNMENT_WEIGHT_R

        ux = vel.x + coh_x + sep_x + ali_x
        uy = vel.y + coh_y + sep_y + ali_y
        sp2 = ux * ux + uy * uy
        if sp2 < MIN_VELOCITY * MIN_VELOCITY
          s = MIN_VELOCITY / Math.sqrt(sp2)
          ux *= s; uy *= s
        elsif sp2 > MAX_VELOCITY * MAX_VELOCITY
          s = MAX_VELOCITY / Math.sqrt(sp2)
          ux *= s; uy *= s
        end
        vel.x = ux
        vel.y = uy
      end

      pos.x += vel.x; pos.y += vel.y
      pos.x = (pos.x + RESOLUTION[:w]) % RESOLUTION[:w]
      pos.y = (pos.y + RESOLUTION[:h]) % RESOLUTION[:h]
      vel.x *= scale
      vel.y *= scale
    end
  end
end