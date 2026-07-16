require 'lib/drecs.rb'

# Native systems require @-ivar components (Drecs.component), not Struct —
# register_native_system enforces this.
NSPosition = Drecs.component(:x, :y)
NSVelocity = Drecs.component(:x, :y)

# These tests exercise the Ruby-side wiring of register_native_system
# and run_native_system. They intentionally do NOT depend on the
# drecs_parallel C extension being loaded - that requires a built DLL
# and is exercised by the samples/native_systems sample. Here we just
# verify registration metadata, error paths, and shape.

def test_native_system_registration(args, assert)
  world = Drecs::World.new
  world.spawn(NSPosition.new(0.0, 0.0), NSVelocity.new(1.0, 2.0))

  ret = world.register_native_system(
    :integrate,
    module_name: "MySystems",
    kernel:      :integrate_motion,
    reads:       [[NSPosition, :x], [NSPosition, :y], [NSVelocity, :x], [NSVelocity, :y]],
    writes:      [[NSPosition, :x], [NSPosition, :y]],
    threads:     2,
  )
  assert.equal! ret, :integrate, "register_native_system returns the symbol name"

  sys = world.native_systems[:integrate]
  assert.true! sys, "native system stored under its symbol"
  assert.equal! sys[:module_name], "MySystems"
  assert.equal! sys[:kernel], :integrate_motion
  assert.equal! sys[:threads], 2
  assert.equal! sys[:reads].length, 4
  assert.equal! sys[:writes].length, 2
  assert.true! sys[:union].include?(NSPosition)
  assert.true! sys[:union].include?(NSVelocity)
  # union is sorted by class name (SignatureHelper#normalize_signature)
  assert.equal! sys[:union], [NSPosition, NSVelocity]
end

def test_native_system_requires_components(args, assert)
  world = Drecs::World.new
  raised = false
  begin
    world.register_native_system(
      :empty,
      module_name: "MySystems",
      kernel:      :noop,
      reads:       [],
      writes:      [],
    )
  rescue ArgumentError
    raised = true
  end
  assert.true! raised, "registering a native system with no reads/writes should raise"
end

def test_run_native_system_unknown(args, assert)
  world = Drecs::World.new
  raised = false
  begin
    world.run_native_system(:nope)
  rescue ArgumentError
    raised = true
  end
  assert.true! raised, "running an unknown native system should raise ArgumentError"
end

def test_run_native_system_without_runtime(args, assert)
  world = Drecs::World.new
  world.spawn(NSPosition.new(0.0, 0.0), NSVelocity.new(1.0, 2.0))
  world.register_native_system(
    :integrate,
    module_name: "MySystems",
    kernel:      :integrate_motion,
    reads:       [[NSVelocity, :x]],
    writes:      [[NSPosition, :x]],
  )

  # Without the C extension loaded (i.e. Drecs::Parallel.run_kernel is
  # not defined), run_native_system must raise a clear error rather than
  # silently doing nothing.
  # NOTE: `defined?` is not supported by DragonRuby's mruby; use const_defined?.
  if !::Drecs.const_defined?(:Parallel) || !::Drecs::Parallel.respond_to?(:run_kernel)
    raised = false
    begin
      world.run_native_system(:integrate, dt: 0.016)
    rescue RuntimeError => e
      raised = e.message.include?("drecs_parallel")
    end
    assert.true! raised, "run_native_system should raise when runtime not loaded"
  else
    puts "drecs_parallel runtime is loaded; skipping unloaded-runtime assertion"
  end
end
