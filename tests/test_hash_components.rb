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

def test_destroy_query_hash_components args, assert
  world = Drecs::World.new

  world.spawn({ position: { x: 10, y: 20 }, velocity: { dx: 1, dy: 2 } })
  world.spawn({ position: { x: 5, y: 15 }, velocity: { dx: 3, dy: 4 } })
  world.spawn({ position: { x: 1, y: 2 } })

  world.destroy_query(:position, :velocity)

  count = 0
  world.query(:position) do |entity_ids, positions|
    count = entity_ids.length
  end

  assert.equal! count, 1
end

def test_destroy_from_query_hash_components args, assert
  world = Drecs::World.new

  world.spawn({ position: { x: 10, y: 20 }, velocity: { dx: 1, dy: 2 } })
  world.spawn({ position: { x: 5, y: 15 }, velocity: { dx: 3, dy: 4 } })
  world.spawn({ position: { x: 1, y: 2 } })

  q = world.query(:position, :velocity)
  world.destroy_from_query(q)

  count = 0
  world.query(:position) do |entity_ids, positions|
    count = entity_ids.length
  end

  assert.equal! count, 1
end

def test_signature_is_frozen args, assert
  world = Drecs::World.new
  entity = world.spawn({ position: { x: 1, y: 2 } })

  loc = world.instance_variable_get(:@entity_locations)[entity]
  archetype = loc[:archetype]

  assert.equal! archetype.component_classes.frozen?, true
end

def test_spawn_duplicate_components_raises_when_validation_enabled args, assert
  position_klass = if Object.const_defined?(:DrecsTestPosition)
    Object.const_get(:DrecsTestPosition)
  else
    Object.const_set(:DrecsTestPosition, Struct.new(:x, :y))
  end

  world = Drecs::World.new(validate_components: true)

  begin
    world.spawn(position_klass.new(1, 2), position_klass.new(3, 4))
    assert.equal! true, false
  rescue ArgumentError
    assert.equal! true, true
  end
end
