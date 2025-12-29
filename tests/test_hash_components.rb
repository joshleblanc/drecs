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

def test_query_with_clause_filters_without_returning_components args, assert
  world = Drecs::World.new

  a = world.spawn({ position: { x: 1, y: 2 }, tag: :a })
  b = world.spawn({ position: { x: 3, y: 4 } })
  c = world.spawn({ position: { x: 5, y: 6 }, tag: :c })

  ids = []
  positions_seen = 0

  world.query(:position, with: [:tag]) do |entity_ids, positions|
    ids.concat(entity_ids)
    positions_seen += positions.length
  end

  assert.equal! ids.sort, [a, c].sort
  assert.equal! positions_seen, 2

  yielded_arity = world.query(:position, with: [:tag]).first.length
  assert.equal! yielded_arity, 2
end

def test_each_entity_with_clause_filters_without_yielding_components args, assert
  world = Drecs::World.new

  a = world.spawn({ position: { x: 1, y: 2 }, tag: :a })
  b = world.spawn({ position: { x: 3, y: 4 } })

  ids = []
  world.each_entity(:position, with: [:tag]) do |id, pos|
    ids << id
  end

  assert.equal! ids, [a]
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

def test_component_accessors_and_aliases args, assert
  world = Drecs::World.new

  entity = world.spawn({ position: { x: 1, y: 2 } })

  assert.equal! world[entity, :position], { x: 1, y: 2 }

  world[entity, :position] = { x: 10, y: 20 }
  assert.equal! world.get(entity, :position), { x: 10, y: 20 }

  world.set_component(entity, :velocity, { dx: 3, dy: 4 })
  assert.equal! world.get_component(entity, :velocity), { dx: 3, dy: 4 }

  assert.equal! world.exists?(entity), true
  assert.equal! world.alive?(entity), true
  assert.equal! world.has?(entity, :position), true
  assert.equal! world.component?(entity, :velocity), true
end

def test_query_helpers_and_bulk_ops args, assert
  world = Drecs::World.new

  e1 = world.spawn({ position: { x: 1, y: 2 }, velocity: { dx: 1, dy: 1 } })
  e2 = world.spawn({ position: { x: 3, y: 4 }, velocity: { dx: 2, dy: 2 } })
  e3 = world.spawn({ position: { x: 5, y: 6 } })

  assert.equal! world.count(:position), 3
  assert.equal! world.count(:position, :velocity), 2

  ids = world.ids(:position, :velocity)
  assert.equal! ids.sort, [e1, e2].sort

  per_entity_count = 0
  world.each(:position) do |id, pos|
    per_entity_count += 1
  end
  assert.equal! per_entity_count, 3

  result = world.first(:position, :velocity)
  assert.true! result != nil

  world.remove_all(:velocity)
  assert.equal! world.count(:position, :velocity), 0

  world.destroy_all(:position)
  assert.equal! world.entity_count, 0

  world.spawn({ position: { x: 1, y: 2 } })
  world.spawn({ position: { x: 3, y: 4 } })
  world.clear!
  assert.equal! world.entity_count, 0
end

def test_flush_defer_only_runs_once args, assert
  world = Drecs::World.new

  count = 0
  world.defer { |_w| count += 1 }

  world.flush_defer!
  world.flush_defer!

  assert.equal! count, 1
end

def test_flush_defer_is_safe_when_deferring_during_flush args, assert
  world = Drecs::World.new

  count = 0
  world.defer do |w|
    count += 1
    w.defer { |_w2| count += 1 }
  end

  world.flush_defer!
  assert.equal! count, 1

  world.flush_defer!
  assert.equal! count, 2
end

def test_each_chunk_and_create_alias args, assert
  world = Drecs::World.new

  world.create({ position: { x: 1, y: 2 } })
  world.create({ position: { x: 3, y: 4 } })

  count = 0
  world.each_chunk(:position) do |entity_ids, positions|
    count += entity_ids.length
  end

  assert.equal! count, 2
end

def test_system_step args, assert
  world = Drecs::World.new

  called = 0
  world.add_system do |_w, _args|
    called += 1
  end

  world.step(nil)
  assert.equal! called, 1
end
