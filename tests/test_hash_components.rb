def test_hash_spawn args, assert
  world = Drecs::World.new

  entity1 = world.spawn({ position: { x: 10, y: 20 }, velocity: { dx: 1, dy: 2 } })

  position = world.get_component(entity1, :position)
  velocity = world.get_component(entity1, :velocity)

  assert.equal! position, { x: 10, y: 20 }
  assert.equal! velocity, { dx: 1, dy: 2 }
end

def test_hash_query args, assert
  world = Drecs::World.new

  entity1 = world.spawn({ position: { x: 10, y: 20 }, velocity: { dx: 1, dy: 2 } })
  entity2 = world.spawn({ position: { x: 5, y: 15 }, velocity: { dx: 3, dy: 4 } })

  count = 0
  world.query(:position, :velocity) do |entity_ids, positions, velocities|
    count = entity_ids.length
  end

  assert.equal! count, 2
end

def test_hash_add_component args, assert
  world = Drecs::World.new

  entity = world.spawn({ position: { x: 5, y: 15 } })
  world.add_component(entity, :velocity, { dx: 3, dy: 4 })

  velocity = world.get_component(entity, :velocity)
  assert.equal! velocity, { dx: 3, dy: 4 }

  count = 0
  world.query(:position, :velocity) do |entity_ids, positions, velocities|
    count = entity_ids.length
  end
  assert.equal! count, 1
end

def test_hash_set_components args, assert
  world = Drecs::World.new

  entity = world.spawn({ position: { x: 10, y: 20 }, velocity: { dx: 1, dy: 2 } })
  world.set_components(entity, { position: { x: 100, y: 200 } })

  position = world.get_component(entity, :position)
  assert.equal! position, { x: 100, y: 200 }

  velocity = world.get_component(entity, :velocity)
  assert.equal! velocity, { dx: 1, dy: 2 }
end
