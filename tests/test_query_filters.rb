require 'lib/drecs.rb'

def test_query_without_filter_struct_components(args, assert)
  position_klass = if Object.const_defined?(:DrecsQFPosition)
    Object.const_get(:DrecsQFPosition)
  else
    Object.const_set(:DrecsQFPosition, Struct.new(:x, :y))
  end

  frozen_klass = if Object.const_defined?(:DrecsQFFrozen)
    Object.const_get(:DrecsQFFrozen)
  else
    Object.const_set(:DrecsQFFrozen, Struct.new)
  end

  world = Drecs::World.new

  a = world.spawn(position_klass.new(1, 2))
  b = world.spawn(position_klass.new(3, 4), frozen_klass.new)

  ids = []
  world.query(position_klass, without: frozen_klass) do |entity_ids, _positions|
    ids.concat(entity_ids)
  end

  assert.equal! ids, [a]

  enum_ids = world.query(position_klass, without: frozen_klass).map { |id, _pos| id }
  assert.equal! enum_ids, [a]

  q = world.query_for(position_klass, without: frozen_klass)
  cached_ids = []
  q.each do |entity_ids, _positions|
    cached_ids.concat(entity_ids)
  end

  assert.equal! cached_ids, [a]
end

def test_query_any_filter_struct_components(args, assert)
  position_klass = if Object.const_defined?(:DrecsQFPosition2)
    Object.const_get(:DrecsQFPosition2)
  else
    Object.const_set(:DrecsQFPosition2, Struct.new(:x, :y))
  end

  player_klass = if Object.const_defined?(:DrecsQFPlayer)
    Object.const_get(:DrecsQFPlayer)
  else
    Object.const_set(:DrecsQFPlayer, Struct.new)
  end

  enemy_klass = if Object.const_defined?(:DrecsQFEnemy)
    Object.const_get(:DrecsQFEnemy)
  else
    Object.const_set(:DrecsQFEnemy, Struct.new)
  end

  world = Drecs::World.new

  a = world.spawn(position_klass.new(1, 2), player_klass.new)
  b = world.spawn(position_klass.new(3, 4), enemy_klass.new)
  c = world.spawn(position_klass.new(5, 6))

  ids = []
  world.query(position_klass, any: [player_klass, enemy_klass]) do |entity_ids, _positions|
    ids.concat(entity_ids)
  end

  assert.equal! ids.sort, [a, b].sort
  assert.equal! ids.include?(c), false

  q = world.query_for(position_klass, any: [player_klass, enemy_klass])
  cached_ids = []
  q.each do |entity_ids, _positions|
    cached_ids.concat(entity_ids)
  end

  assert.equal! cached_ids.sort, [a, b].sort
end

def test_query_filters_hash_components(args, assert)
  world = Drecs::World.new

  a = world.spawn({ position: { x: 1, y: 2 }, foo: 1 })
  b = world.spawn({ position: { x: 3, y: 4 }, bar: 2 })
  c = world.spawn({ position: { x: 5, y: 6 } })

  without_ids = []
  world.query(:position, without: [:foo]) do |entity_ids, _positions|
    without_ids.concat(entity_ids)
  end
  assert.equal! without_ids.sort, [b, c].sort

  any_ids = []
  world.query(:position, any: [:foo, :bar]) do |entity_ids, _positions|
    any_ids.concat(entity_ids)
  end
  assert.equal! any_ids.sort, [a, b].sort
end
