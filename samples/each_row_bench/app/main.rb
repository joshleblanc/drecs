# Benchmarks the per-row iteration of each_entity: pure Ruby fallback
# vs the C path via Drecs::Parallel.each_row.
#
# Usage: dragonruby.exe drecs --sample each_row_bench 5000 50
# Args: N_ENTITIES N_ITERS

LOG = 'each_row_bench_log.txt'
File.open(LOG, 'w') { |f| f.puts "[bench] start" }

# Load the drecs_parallel C extension so we can bench each_row.
begin
  DR.dlopen 'drecs_parallel'
  Drecs::Parallel.load
rescue => e
  File.open(LOG, 'a') { |f| f.puts "[bench] drecs_parallel load failed: #{e.message}" }
end

# DR doesn't expose ARGV; command-line args come via $gtk.cli_arguments.
cli_args = $gtk.cli_arguments
File.open(LOG, 'a') { |f| f.puts "[bench] cli_args=#{cli_args.inspect}" }

N_ENTITIES = (cli_args[0] || 40_000).to_i
N_ITERS    = (cli_args[1] || 100).to_i

class BenchPosition < Drecs.component(:x, :y); end
class BenchSize     < Drecs.component(:w, :h); end
class BenchColor    < Drecs.component(:r, :g, :b, :a); end

def log(msg)
  puts msg
  File.open(LOG, 'a') { |f| f.puts msg }
end

# Pure-Ruby fallback (the original World#each_entity inner loop).
def ruby_each_row(entity_ids, stores, &block)
  i = 0
  len = entity_ids.length
  num_stores = stores.length
  while i < len
    case num_stores
    when 1 then block.call(entity_ids[i], stores[0][i])
    when 2 then block.call(entity_ids[i], stores[0][i], stores[1][i])
    when 3 then block.call(entity_ids[i], stores[0][i], stores[1][i], stores[2][i])
    when 4 then block.call(entity_ids[i], stores[0][i], stores[1][i], stores[2][i], stores[3][i])
    else
      block.call(entity_ids[i], *stores.map { |s| s[i] })
    end
    i += 1
  end
end

def tick(args)
  return if args.state.done

  log "[bench] tick fired, N_ENTITIES=#{N_ENTITIES} N_ITERS=#{N_ITERS}"

  world = Drecs::World.new
  N_ENTITIES.times do |i|
    world.spawn(
      BenchPosition.new(i.to_f, i.to_f),
      BenchSize.new(5.0, 5.0),
      BenchColor.new(i % 255, (i * 7) % 255, (i * 13) % 255, 255)
    )
  end
  log "[bench] spawned #{N_ENTITIES} entities"

  counter = 0
  block = ->(id, pos, size, color) { counter += 1 }

  # Time Ruby path
  t0 = Time.now.to_f
  N_ITERS.times do
    world.each_chunk(BenchPosition, BenchSize, BenchColor) do |entity_ids, *stores|
      ruby_each_row(entity_ids, stores, &block)
    end
  end
  ruby_time = Time.now.to_f - t0
  log format("[bench] Ruby each_row: %8.3fs  (%6.0f iter/sec, %d block fires)",
              ruby_time, N_ITERS / ruby_time, counter)

  # Time C path
  counter = 0
  t0 = Time.now.to_f
  N_ITERS.times do
    world.each_chunk(BenchPosition, BenchSize, BenchColor) do |entity_ids, *stores|
      Drecs::Parallel.each_row(entity_ids, stores, &block)
    end
  end
  c_time = Time.now.to_f - t0
  speedup = ruby_time / c_time
  log format("[bench] C each_row:    %8.3fs  (%6.0f iter/sec, %d block fires)  [%.2fx faster]",
              c_time, N_ITERS / c_time, counter, speedup)
  log "[bench] done"

  args.state.done = true
end