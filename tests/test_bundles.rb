require 'lib/drecs.rb'

BundlePosition = Struct.new(:x, :y)
BundleVelocity = Struct.new(:dx, :dy)

def test_spawn_bundle_struct_ordered(args, assert)
  world = Drecs::World.new
  b = Drecs.bundle(BundlePosition, BundleVelocity)

  id = world.spawn_bundle(b, BundlePosition.new(1, 2), BundleVelocity.new(3, 4))

  pos = world.get_component(id, BundlePosition)
  vel = world.get_component(id, BundleVelocity)

  assert.equal! pos.x, 1
  assert.equal! pos.y, 2
  assert.equal! vel.dx, 3
  assert.equal! vel.dy, 4
end

def test_spawn_bundle_struct_unordered(args, assert)
  world = Drecs::World.new
  b = Drecs.bundle(BundlePosition, BundleVelocity)

  id = world.spawn_bundle(b, BundleVelocity.new(3, 4), BundlePosition.new(1, 2))

  pos = world.get_component(id, BundlePosition)
  vel = world.get_component(id, BundleVelocity)

  assert.equal! pos.x, 1
  assert.equal! pos.y, 2
  assert.equal! vel.dx, 3
  assert.equal! vel.dy, 4
end

def test_spawn_bundle_block_form(args, assert)
  world = Drecs::World.new
  b = Drecs.bundle(BundlePosition, BundleVelocity)

  id = world.spawn_bundle(b) do |bb|
    bb[BundlePosition] = BundlePosition.new(10, 20)
    bb[BundleVelocity] = BundleVelocity.new(1, 2)
  end

  pos = world.get_component(id, BundlePosition)
  vel = world.get_component(id, BundleVelocity)

  assert.equal! pos.x, 10
  assert.equal! pos.y, 20
  assert.equal! vel.dx, 1
  assert.equal! vel.dy, 2
end

def test_spawn_bundle_hash_components(args, assert)
  world = Drecs::World.new
  b = Drecs.bundle(:position, :velocity)

  id = world.spawn_bundle(b, { position: { x: 1, y: 2 }, velocity: { dx: 3, dy: 4 } })

  assert.equal! world.get_component(id, :position), { x: 1, y: 2 }
  assert.equal! world.get_component(id, :velocity), { dx: 3, dy: 4 }
end
