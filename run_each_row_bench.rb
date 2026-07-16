# Microbenchmark for Drecs::Parallel.each_row (C path) vs the
# pure-Ruby fallback in World#each_entity. Spawns N entities, runs
# each_entity N times, times the whole thing.
#
# Run with system Ruby (no DR needed for the timing harness):
#   ruby run_each_row_bench.rb
# Output: pure-Ruby iterations/sec vs C-iter iterations/sec.

$LOAD_PATH.unshift "."
require "lib/drecs"

# drecs uses `Array.each(arr) { block }` — a one-arg form that iterates
# the array. System Ruby doesn't have it built in.
unless Array.respond_to?(:each)
  def Array.each(arr, &block)
    arr.each(&block)
  end
end

N_ENTITIES = (ARGV[0] || 40_000).to_i
N_ITERS    = (ARGV[1] || 200).to_i

class BenchPosition < Drecs.component(:x, :y)
end
class BenchSize     < Drecs.component(:w, :h)
end
class BenchColor    < Drecs.component(:r, :g, :b, :a)
end

def build_world(n)
  world = Drecs::World.new
  n.times do |i|
    world.spawn(
      BenchPosition.new(i.to_f, i.to_f),
      BenchSize.new(5.0, 5.0),
      BenchColor.new(i % 255, (i * 7) % 255, (i * 13) % 255, 255)
  end
  world
end

# Pure-Ruby fallback: the case-when loop that World#each_entity used
# before the C port. Verifies the optimization actually matters.
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

# Block that does the absolute minimum work — a single ivar read. This
# measures the per-call dispatch cost, not the user's block work.
work_counter = 0
block = ->(id, pos, size, color) { work_counter += 1 }

world = build_world(N_ENTITIES)
puts "Spawned #{N_ENTITIES} entities, #{N_ITERS} iterations of each_entity"

# Time the pure-Ruby path
t0 = Time.now
N_ITERS.times do
  world.query(BenchPosition, BenchSize, BenchColor) do |entity_ids, *stores|
    ruby_each_row(entity_ids, stores, &block)
  end
end
ruby_time = Time.now - t0

puts format("Ruby each_row:  %8.3fs  (%6.0f iter/sec)",
            ruby_time, N_ITERS / ruby_time)

# Time the C path (only meaningful if the drecs_parallel extension is loaded)
if defined?(Drecs::Parallel) && Drecs::Parallel.respond_to?(:each_row)
  t0 = Time.now
  N_ITERS.times do
    world.query(BenchPosition, BenchSize, BenchColor) do |entity_ids, *stores|
      Drecs::Parallel.each_row(entity_ids, stores, &block)
    end
  end
  c_time = Time.now - t0

  speedup = ruby_time / c_time
  puts format("C each_row:     %8.3fs  (%6.0f iter/sec)  [%.2fx faster]",
              c_time, N_ITERS / c_time, speedup)
else
  puts "C path not available (drecs_parallel extension not loaded)"
end

puts "block fired #{work_counter} times total (expected: #{(N_ITERS * N_ENTITIES * (defined?(Drecs::Parallel) && Drecs::Parallel.respond_to?(:each_row) ? 2 : 1))})"