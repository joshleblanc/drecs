require 'lib/drecs.rb'

class CDPosition < Struct.new(:x, :y); end
class CDVelocity < Struct.new(:dx, :dy); end

# Change detection semantics:
# - Spawning marks components changed at the current world change_tick.
# - Mutating via set_component/set_components/add_component marks touched components changed at the current tick.
# - Querying with changed: returns only entities whose specified components were changed at the current tick.

def test_change_detection_spawn_and_set_component(args, assert)
  world = Drecs::World.new

  # Baseline tick
  world.advance_change_tick!
  e1 = world.spawn(CDPosition.new(0, 0))
  e2 = world.spawn(CDPosition.new(10, 10))

  ids = world.ids(CDPosition, changed: [CDPosition])
  assert.equal! ids.sort, [e1, e2].sort

  # Next tick: nothing changed
  world.advance_change_tick!
  ids = world.ids(CDPosition, changed: [CDPosition])
  assert.equal! ids, []

  # Mutate one entity in this tick
  world.set_component(e1, CDPosition.new(5, 5))
  ids = world.ids(CDPosition, changed: [CDPosition])
  assert.equal! ids, [e1]
end

def test_change_detection_set_components_only_marks_touched(args, assert)
  world = Drecs::World.new
  world.advance_change_tick!

  e = world.spawn(CDPosition.new(0, 0), CDVelocity.new(1, 1))

  # Move to next tick
  world.advance_change_tick!

  # Only update velocity
  world.set_components(e, CDVelocity.new(2, 3))

  pos_changed = world.ids(CDPosition, changed: [CDPosition])
  vel_changed = world.ids(CDVelocity, changed: [CDVelocity])

  assert.equal! pos_changed, []
  assert.equal! vel_changed, [e]
end

# Covers hash/symbol component keys as well.

def test_change_detection_hash_components(args, assert)
  world = Drecs::World.new
  world.advance_change_tick!

  e = world.spawn({ position: { x: 0, y: 0 } })

  ids = world.ids(:position, changed: [:position])
  assert.equal! ids, [e]

  world.advance_change_tick!
  ids = world.ids(:position, changed: [:position])
  assert.equal! ids, []

  world.set_component(e, :position, { x: 10, y: 20 })
  ids = world.ids(:position, changed: [:position])
  assert.equal! ids, [e]
end
