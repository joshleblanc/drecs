require 'lib/drecs.rb'

def test_scheduled_system_order_after(args, assert)
  world = Drecs::World.new
  log = []

  world.add_system(:input) { |_w, _a| log << :input }
  world.add_system(:movement, after: :input) { |_w, _a| log << :movement }
  world.add_system(:render, after: :movement) { |_w, _a| log << :render }

  world.tick(nil)

  assert.equal! log, [:input, :movement, :render]
end

def test_scheduled_system_order_before(args, assert)
  world = Drecs::World.new
  log = []

  world.add_system(:render) { |_w, _a| log << :render }
  world.add_system(:input, before: :render) { |_w, _a| log << :input }

  world.tick(nil)

  assert.equal! log, [:input, :render]
end

def test_scheduled_system_run_condition(args, assert)
  world = Drecs::World.new
  log = []

  world.insert_resource(:paused, true)

  world.add_system(:movement, if: ->(w, _args) { !w.resource(:paused) }) { |_w, _a| log << :movement }
  world.add_system(:render) { |_w, _a| log << :render }

  world.tick(nil)
  assert.equal! log, [:render]

  world.insert_resource(:paused, false)
  world.tick(nil)
  assert.equal! log, [:render, :movement, :render]
end

def test_scheduled_system_unknown_dependency_raises(args, assert)
  world = Drecs::World.new

  world.add_system(:movement, after: :input) { |_w, _a| }

  begin
    world.tick(nil)
    assert.equal! true, false
  rescue ArgumentError
    assert.equal! true, true
  end
end

def test_scheduled_system_cycle_detection_raises(args, assert)
  world = Drecs::World.new

  world.add_system(:a, after: :b) { |_w, _a| }
  world.add_system(:b, after: :a) { |_w, _a| }

  begin
    world.tick(nil)
    assert.equal! true, false
  rescue ArgumentError
    assert.equal! true, true
  end
end
