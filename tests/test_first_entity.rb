def test_first_entity_with_results args, assert
  world = Drecs::World.new

  entity1 = world.spawn({ position: { x: 10, y: 20 }, velocity: { dx: 1, dy: 2 } })
  entity2 = world.spawn({ position: { x: 5, y: 15 }, velocity: { dx: 3, dy: 4 } })

  result = world.first_entity(:position, :velocity)

  assert.true! result != nil, "Expected first_entity to return a result"
  assert.equal! result.length, 3, "Expected [entity_id, position, velocity]"

  entity_id, position, velocity = result
  assert.true! [entity1, entity2].include?(entity_id), "Expected entity_id to be one of the spawned entities"
  assert.true! position.is_a?(Hash), "Expected position to be a hash"
  assert.true! velocity.is_a?(Hash), "Expected velocity to be a hash"
end

def test_first_entity_with_block args, assert
  world = Drecs::World.new

  entity1 = world.spawn({ position: { x: 10, y: 20 }, velocity: { dx: 1, dy: 2 } })
  entity2 = world.spawn({ position: { x: 5, y: 15 }, velocity: { dx: 3, dy: 4 } })

  yielded_entity_id = nil
  yielded_position = nil
  yielded_velocity = nil

  returned_id = world.first_entity(:position, :velocity) do |entity_id, position, velocity|
    yielded_entity_id = entity_id
    yielded_position = position
    yielded_velocity = velocity
  end

  assert.true! yielded_entity_id != nil, "Expected block to be called"
  assert.true! [entity1, entity2].include?(yielded_entity_id), "Expected entity_id to be one of the spawned entities"
  assert.equal! returned_id, yielded_entity_id, "Expected method to return the entity_id when block given"
  assert.true! yielded_position.is_a?(Hash), "Expected position to be a hash"
  assert.true! yielded_velocity.is_a?(Hash), "Expected velocity to be a hash"
end

def test_first_entity_no_match args, assert
  world = Drecs::World.new

  entity1 = world.spawn({ position: { x: 10, y: 20 } })

  result = world.first_entity(:position, :velocity)

  assert.equal! result, nil, "Expected nil when no entities match"
end

def test_first_entity_empty_world args, assert
  world = Drecs::World.new

  result = world.first_entity(:position)

  assert.equal! result, nil, "Expected nil for empty world"
end
