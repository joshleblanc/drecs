# native_bench sample
#
# Compares pure-Ruby ECS integration against the drecs native-systems path
# (real C kernels running across SDL3 threads). For a given entity count,
# it runs K iterations of:
#   expensive_force (heavy: 100 substeps of spring-damper per row)
# in each of:
#   - pure Ruby  (via each_entity)
#   - native with threads: 1, 2, 4, 8
# and verifies the results agree within a small epsilon, then reports a
# per-iteration timing table to native_bench_results.txt.
#
# Before running, build the kernel with:
#   samples\native_bench\build.bat
#
# Run with:
#   dragonruby.exe drecs --sample native_bench
#
# Adjust ENTITY_COUNTS and ITERATIONS in the constants below to taste.

ENTITY_COUNTS   = [2_000, 10_000, 50_000]
ITERATIONS      = 5
THREAD_COUNTS   = [1, 2, 4, 8]
EPSILON         = 1.0e-3   # heavy compute accumulates more float drift

BenchPosition = Drecs.component(:x, :y)
BenchVelocity = Drecs.component(:x, :y)

INNER_STEPS = 100
SPRING_K    = 0.5
DAMPING     = 0.999

def spawn_deterministic(world, n)
  s = 0x12345
  i = 0
  while i < n
    s = (s * 1103515245 + 12345) & 0x7fffffff
    px = (s % 1280).to_f
    s = (s * 1103515245 + 12345) & 0x7fffffff
    py = (s % 720).to_f
    s = (s * 1103515245 + 12345) & 0x7fffffff
    vx = ((s % 200) - 100).to_f
    s = (s * 1103515245 + 12345) & 0x7fffffff
    vy = ((s % 200) - 100).to_f
    world.spawn(BenchPosition.new(px, py), BenchVelocity.new(vx, vy))
    i += 1
  end
end

# Ruby reference: 100 inner iterations of spring-damper verlet per entity.
# Same arithmetic as the C expensive_force kernel.
def pure_ruby_heavy(world, dt)
  dt_sub = dt / INNER_STEPS
  world.each_entity(BenchPosition, BenchVelocity) do |_id, pos, vel|
    x = pos.x; y = pos.y
    u = vel.x; v = vel.y
    k = 0
    while k < INNER_STEPS
      fx = -SPRING_K * x
      fy = -SPRING_K * y
      u += fx * dt_sub
      v += fy * dt_sub
      x += u  * dt_sub
      y += v  * dt_sub
      u *= DAMPING
      v *= DAMPING
      k += 1
    end
    vel.x = u
    vel.y = v
  end
end

def now_seconds
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
rescue
  Time.now.to_f
end

def sample_state(world, sample_size)
  ids = world.ids(BenchPosition)
  ids.first(sample_size).map { |id| [id, world.get(id, BenchPosition), world.get(id, BenchVelocity)] }
end

def states_match(s_ruby, s_native, eps)
  # Compare by POSITION, not by ID. The heavy kernel doesn't write to
  # position, so each entity's pos.x/pos.y stays at its initial value
  # across all iterations. That makes position a stable identity even
  # when entity IDs are scrambled by restore/reuse patterns.
  ruby_by_pos = {}
  s_ruby.each { |_id, pos, vel| ruby_by_pos[[pos.x, pos.y]] = vel }
  native_by_pos = {}
  s_native.each { |_id, pos, vel| native_by_pos[[pos.x, pos.y]] = vel }

  ruby_by_pos.each do |pos, rvel|
    nvel = native_by_pos[pos]
    return false if nvel.nil?
    return false if (rvel.x - nvel.x).abs > eps || (rvel.y - nvel.y).abs > eps
  end
  ruby_by_pos.length == native_by_pos.length
end

def sample_state_all(world)
  # Sample EVERY entity (we need full coverage to verify correctness).
  ids = world.ids(BenchPosition)
  ids.map { |id| [id, world.get(id, BenchPosition), world.get(id, BenchVelocity)] }
end

def log(msg)
  $stdout.puts msg rescue nil
  begin
    File.open('native_bench_log.txt', 'a') { |f| f.puts msg }
  rescue
  end
end

def boot(args)
  log "[native_bench] booting..."

  begin
    DR.dlopen "drecs_parallel"
    Drecs::Parallel.load
    log "[native_bench] parallel loaded ok"
  rescue StandardError => e
    log "[native_bench] drecs_parallel FAILED: #{e.message}"
    args.state[:failed] = true
    return
  end

  begin
    DR.dlopen "bench_kernel"
    log "[native_bench] bench_kernel loaded ok (#{Object.const_defined?(:BenchSystems)})"
  rescue StandardError => e
    log "[native_bench] bench_kernel FAILED: #{e.message}"
    args.state[:failed] = true
    return
  end

  args.state[:failed] = false
  args.state[:phase]  = :setup
end

def tick(args)
  log "[native_bench] tick phase=#{args.state[:phase].inspect}" if args.state[:phase]
  boot(args) unless args.state[:phase]

  if args.state[:failed]
    log "[native_bench] setup failed, exiting"
    $gtk.exit
    return
  end

  begin
    case args.state[:phase]
    when :setup
      run_setup(args)
    when :measure_ruby
      run_ruby_measurement(args)
    when :measure_native
      run_native_measurement(args)
    when :report
      write_report(args)
      $gtk.exit
    end
  rescue => e
    log "[native_bench] TICK EXCEPTION: #{e.class}: #{e.message}"
    log e.backtrace.first(5).join("\n")
    $gtk.exit
  end
end

def run_setup(args)
  warmup_world = Drecs::World.new
  spawn_deterministic(warmup_world, 500)
  3.times { pure_ruby_heavy(warmup_world, 1.0 / 60.0) }

  args.state[:results] = []
  args.state[:cursor]  = { entity_idx: 0, thread_idx: -1 }
  args.state[:phase]   = :measure_ruby
end

def run_ruby_measurement(args)
  cursor = args.state[:cursor]
  n = ENTITY_COUNTS[cursor[:entity_idx]]

  # Spawn the canonical world and snapshot it. The native measurement
  # restores from this snapshot, which re-IDs entities in a different
  # order — so to compare apples to apples, Ruby should also work from
  # a *restored* world with the same ID mapping.
  source_world = Drecs::World.new
  spawn_deterministic(source_world, n)
  initial_snap = source_world.snapshot

  # The Ruby reference uses a restored world (same ID mapping as Native).
  world = Drecs::World.new
  world.restore(initial_snap)

  # Warmup — runs the SAME number of iterations as the native warmup
  # so the timed iterations start from equivalent cold-state caches.
  pure_ruby_heavy(world, 1.0 / 60.0)

  t0 = now_seconds
  iter = 0
  while iter < ITERATIONS
    pure_ruby_heavy(world, 1.0 / 60.0)
    iter += 1
  end
  t1 = now_seconds
  ruby_ms = ((t1 - t0) * 1000.0) / ITERATIONS

  ruby_state_sample = sample_state_all(world)

  args.state[:results] << {
    entities: n,
    ruby_ms_per_iter: ruby_ms,
    ruby_state_sample: ruby_state_sample,
    initial_snap: initial_snap
  }
  log "[native_bench] ruby   n=#{n}  #{ruby_ms.round(3)} ms/iter"

  args.state[:phase] = :measure_native
  args.state[:cursor][:thread_idx] = 0
end

def run_native_measurement(args)
  cursor = args.state[:cursor]
  result = args.state[:results].last
  n = result[:entities]
  ruby_ms = result[:ruby_ms_per_iter]
  t_count = THREAD_COUNTS[cursor[:thread_idx]]
  log "[native_bench] native n=#{n} threads=#{t_count}"

  snap = result[:initial_snap]
  world = Drecs::World.new
  world.restore(snap)
  log "[native_bench]   restored, #{world.entity_count} entities"

  world.register_native_system(
    :heavy,
    module_name: "BenchSystems",
    kernel:      :expensive_force,
    reads:       [[BenchPosition, :x], [BenchPosition, :y],
                  [BenchVelocity, :x], [BenchVelocity, :y]],
    writes:      [[BenchVelocity, :x], [BenchVelocity, :y]],
    threads:     t_count,
  )
  log "[native_bench]   registered, about to warmup"

  # Single-iteration A/B test: run ONE Ruby iteration on a fresh world,
  # then run ONE native iteration on a SEPARATE fresh world. Compare
  # the two states directly (by id). Use completely separate worlds so
  # neither gets extra iterations that would affect the main measurement.
  begin
    ruby_world = Drecs::World.new
    ruby_world.restore(result[:initial_snap])
    pure_ruby_heavy(ruby_world, 1.0 / 60.0)
    ruby_after = sample_state(ruby_world, 8)

    native_world = Drecs::World.new
    native_world.restore(result[:initial_snap])
    native_world.register_native_system(:heavy, module_name: "BenchSystems",
      kernel: :expensive_force,
      reads:  [[BenchPosition, :x], [BenchPosition, :y], [BenchVelocity, :x], [BenchVelocity, :y]],
      writes: [[BenchVelocity, :x], [BenchVelocity, :y]],
      threads: t_count)
    native_world.run_native_system(:heavy, dt: 1.0 / 60.0)
    native_after = sample_state(native_world, 8)

    log "[native_bench]   A/B single iter (Ruby vs Native):"
    4.times do |i|
      next unless ruby_after[i] && native_after[i]
      rid, rpos, rvel = ruby_after[i]
      nid, npos, nvel = native_after[i]
      log "[native_bench]     ruby_id=#{rid}  ruby_vel=(#{rvel.x.round(6)},#{rvel.y.round(6)})  native_id=#{nid}  native_vel=(#{nvel.x.round(6)},#{nvel.y.round(6)})  diff=(#{(rvel.x-nvel.x).abs.round(9)},#{(rvel.y-nvel.y).abs.round(9)})"
    end
  rescue => e
    log "[native_bench]   A/B FAILED: #{e.class}: #{e.message}"
    log e.backtrace.first(8).join("\n")
  end

  # Warm up by running the SAME thing being timed, BUT we restore
  # afterwards so the timed iterations start from initial state.
  # (Skipping this would let cold cache skew the first iteration.)
  begin
    world.run_native_system(:heavy, dt: 1.0 / 60.0)
    log "[native_bench]   warmup ok"
  rescue => e
    log "[native_bench]   WARMUP FAILED: #{e.class}: #{e.message}"
    log e.backtrace.first(10).join("\n")
  end

  # Restore to initial state. This will produce IDs 2000..3999 (one
  # restore-batch ahead of the Ruby world's 0..1999). For correctness
  # verification we'll re-fetch the IDs by *content* instead of by id.

  t0 = now_seconds
  iter = 0
  while iter < ITERATIONS
    world.run_native_system(:heavy, dt: 1.0 / 60.0)
    iter += 1
  end
  t1 = now_seconds
  native_ms = ((t1 - t0) * 1000.0) / ITERATIONS

  native_state_sample = sample_state_all(world)
  matches = states_match(result[:ruby_state_sample], native_state_sample, EPSILON)

  result[:"native_t#{t_count}_ms"]    = native_ms
  result[:"native_t#{t_count}_match"] = matches
  speedup = ruby_ms / native_ms if native_ms > 0
  result[:"speedup_t#{t_count}"]      = speedup

  log "[native_bench]   native t=#{t_count}  #{native_ms.round(3)} ms/iter  match=#{matches}  speedup=#{speedup ? speedup.round(2) : 'n/a'}x"

  if cursor[:thread_idx] + 1 < THREAD_COUNTS.length
    cursor[:thread_idx] += 1
  else
    cursor[:thread_idx] = 0
    cursor[:entity_idx] += 1
    if cursor[:entity_idx] >= ENTITY_COUNTS.length
      args.state[:phase] = :report
    else
      args.state[:phase] = :measure_ruby
    end
  end
end

def write_report(args)
  out = []
  out << "native_bench results (heavy: #{INNER_STEPS} substeps spring-damper)  iterations=#{ITERATIONS}  threads=#{THREAD_COUNTS.inspect}"
  out << "entities | ruby_ms | " + THREAD_COUNTS.map { |t| "native_t#{t}_ms | t#{t}_speedup | t#{t}_match" }.join(" | ")

  (args.state[:results] || []).each do |r|
    row = [r[:entities].to_s, r[:ruby_ms_per_iter].round(3).to_s]
    THREAD_COUNTS.each do |t|
      ms  = r[:"native_t#{t}_ms"]   || 0.0
      sp  = r[:"speedup_t#{t}"]     || 0.0
      mch = r[:"native_t#{t}_match"]
      row << ms.round(3).to_s
      row << (sp > 0 ? "#{sp.round(2)}x" : "n/a")
      row << (mch == nil ? "n/a" : mch.to_s)
    end
    out << row.join(" | ")
  end

  body = out.join("\n") + "\n"
  log "[native_bench] report:\n#{body}"
  begin
    File.write('native_bench_results.txt', body)
    log "[native_bench] results written to native_bench_results.txt"
  rescue => e
    log "[native_bench] FILE WRITE FAILED: #{e.class}: #{e.message}"
  end
end
