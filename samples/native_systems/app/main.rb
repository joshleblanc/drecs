# Sample: native systems
#
# Demonstrates registering a C kernel as an ECS system that drecs runs
# across SDL3 threads. Run with:
#
#   ./run.bat -- --sample native_systems
#
# Before running, build my_systems for your platform; see ext/README.md
# and samples/native_systems/app/my_systems.c.

Position = Drecs.component(:x, :y)
Velocity = Drecs.component(:x, :y)

def flog(msg)
  File.open('C:/source/dragonruby/drecs/ns_log.txt', 'a') { |f| f.puts msg }
end

def boot(args)
  flog "[ns] boot start"

  begin
    DR.dlopen "drecs_parallel"
    Drecs::Parallel.load
    flog "[ns] drecs_parallel loaded, available?=#{Drecs::Parallel.available?}"
  rescue StandardError => e
    flog "[ns] drecs_parallel FAILED: #{e.message}"
  end

  begin
    DR.dlopen "my_systems"
    flog "[ns] my_systems loaded, defined?=#{Object.const_defined?(:MySystems)}"
  rescue StandardError => e
    flog "[ns] my_systems FAILED: #{e.message}"
  end

  # Diagnostic: pointer getter
  begin
    ptr = MySystems._kernel_damp_velocity
    flog "[ns] _kernel_damp_velocity class=#{ptr.class}"
  rescue => e
    flog "[ns] _kernel_damp_velocity FAILED: #{e.message}"
  end

  w = Drecs::World.new
  10.times { w.spawn(Position.new(rand(1280).to_f, rand(720).to_f),
                     Velocity.new((rand * 200) - 100, (rand * 200) - 100)) }

  w.register_native_system(
    :damp,
    module_name: "MySystems",
    kernel:      :damp_velocity,
    reads:       [[Velocity, :x], [Velocity, :y]],
    writes:      [[Velocity, :x], [Velocity, :y]],
    threads:     1,
  )

  flog "[ns] about to call run_native_system"
  w.run_native_system(:damp, dt: 1.0 / 60.0)
  flog "[ns] run_native_system returned"

  $gtk.exit
end

def tick(args)
  boot(args)
end
