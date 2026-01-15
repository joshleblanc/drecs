require 'lib/drecs.rb'

HookPosition = Struct.new(:x, :y)
HookVelocity = Struct.new(:dx, :dy)

def test_on_added_runs_on_spawn(args, assert)
  world = Drecs::World.new
  log = []

  world.on_added(HookPosition) { |_w, _id, _c| log << :position }
  world.on_added(HookVelocity) { |_w, _id, _c| log << :velocity }

  id = world.spawn(HookVelocity.new(1, 2), HookPosition.new(3, 4))

  assert.equal! log, [:position, :velocity]
  assert.equal! world.get_component(id, HookPosition).x, 3
end

def test_on_changed_runs_on_set_and_add(args, assert)
  world = Drecs::World.new
  log = []

  world.on_changed(HookPosition) { |_w, _id, _c| log << :position }
  world.on_changed(HookVelocity) { |_w, _id, _c| log << :velocity }

  id = world.spawn(HookPosition.new(0, 0), HookVelocity.new(1, 1))
  log.clear

  world.set_components(id, HookPosition.new(2, 2))
  assert.equal! log, [:position]

  log.clear
  world.add_component(id, HookVelocity.new(5, 6))
  assert.equal! log, [:velocity]
end

def test_on_removed_runs_on_remove_and_destroy(args, assert)
  world = Drecs::World.new
  log = []

  world.on_removed(HookPosition) { |_w, _id, _c| log << :position }
  world.on_removed(HookVelocity) { |_w, _id, _c| log << :velocity }

  id = world.spawn(HookPosition.new(1, 1), HookVelocity.new(2, 2))

  world.remove_component(id, HookVelocity)
  assert.equal! log, [:velocity]

  log.clear
  world.destroy(id)
  assert.equal! log, [:position]
end

def test_hook_registration_order(args, assert)
  world = Drecs::World.new
  log = []

  world.on_added(HookPosition) { |_w, _id, _c| log << 1 }
  world.on_added(HookPosition) { |_w, _id, _c| log << 2 }

  world.spawn(HookPosition.new(1, 2))

  assert.equal! log, [1, 2]
end

def test_hooks_can_defer_mutations(args, assert)
  world = Drecs::World.new

  world.on_added(HookPosition) do |w, id, _c|
    w.defer { w.destroy(id) }
  end

  id = world.spawn(HookPosition.new(5, 5))
  assert.equal! world.entity_exists?(id), true

  world.flush_defer!
  assert.equal! world.entity_exists?(id), false
end
