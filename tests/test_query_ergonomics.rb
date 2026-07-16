require 'lib/drecs.rb'

class Position < Struct.new(:x, :y); end

def test_query_ergonomics(args, assert)
  world = Drecs::World.new
  id = world.spawn(Position.new(10, 20))

  # `query` is the per-entity (AoS) view in BOTH block and no-block forms.
  res = world.query(Position).first
  assert.equal! res[0].is_a?(Array), false
  assert.equal! res[0], id
  assert.true! res[1].is_a?(Position), "query().first should yield [id, component]"

  # Block form yields one entity at a time: (entity_id, *components).
  world.query(Position) do |entity_id, position|
    assert.equal! entity_id, id
    assert.true! position.is_a?(Position), "query block should yield the component, not an array"
  end

  # each_chunk is the Structure-of-Arrays (SoA) fast path.
  world.each_chunk(Position) do |ids, positions|
    assert.true! ids.is_a?(Array), "each_chunk yield 1 (ids) should be Array"
    assert.true! positions.is_a?(Array), "each_chunk yield 2 (positions) should be Array"
  end
end
