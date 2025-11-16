# Define structs at the top level
Position = Struct.new(:x, :y)
Velocity = Struct.new(:dx, :dy)

def test_append_single_struct_component args, assert
  world = Drecs::World.new

  entity = world << Position.new(10, 20)

  position = world.get_component(entity, Position)
  assert.equal! position.x, 10
  assert.equal! position.y, 20
end

def test_append_multiple_struct_components args, assert
  world = Drecs::World.new

  entity = world << [Position.new(10, 20), Velocity.new(1, 2)]

  position = world.get_component(entity, Position)
  velocity = world.get_component(entity, Velocity)

  assert.equal! position.x, 10
  assert.equal! position.y, 20
  assert.equal! velocity.dx, 1
  assert.equal! velocity.dy, 2
end

def test_append_hash_component args, assert
  world = Drecs::World.new

  entity = world << { position: { x: 10, y: 20 }, velocity: { dx: 1, dy: 2 } }

  position = world.get_component(entity, :position)
  velocity = world.get_component(entity, :velocity)

  assert.equal! position, { x: 10, y: 20 }
  assert.equal! velocity, { dx: 1, dy: 2 }
end

def test_append_returns_entity_id args, assert
  world = Drecs::World.new

  entity1 = world << Position.new(10, 20)
  entity2 = world << Position.new(30, 40)

  assert.true! entity1.is_a?(Integer)
  assert.true! entity2.is_a?(Integer)
  assert.true! entity1 != entity2
end

def test_append_entity_queryable args, assert
  world = Drecs::World.new

  world << [Position.new(10, 20), Velocity.new(1, 2)]
  world << [Position.new(30, 40), Velocity.new(3, 4)]

  count = 0
  world.query(Position, Velocity) do |entity_ids, positions, velocities|
    count = entity_ids.length
  end

  assert.equal! count, 2
end
