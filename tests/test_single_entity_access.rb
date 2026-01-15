require 'lib/drecs.rb'

SinglePosition = Struct.new(:x, :y)
SingleVelocity = Struct.new(:dx, :dy)


def test_get_many_returns_components_in_order(args, assert)
  world = Drecs::World.new
  id = world.spawn(SinglePosition.new(1, 2), SingleVelocity.new(3, 4))

  pos, vel = world.get_many(id, SinglePosition, SingleVelocity)

  assert.true! pos.is_a?(SinglePosition), "Expected position to be SinglePosition"
  assert.true! vel.is_a?(SingleVelocity), "Expected velocity to be SingleVelocity"
  assert.equal! pos.x, 1
  assert.equal! vel.dx, 3
end


def test_get_many_returns_nil_when_missing(args, assert)
  world = Drecs::World.new
  id = world.spawn(SinglePosition.new(1, 2))

  result = world.get_many(id, SinglePosition, SingleVelocity)
  assert.equal! result, nil
end


def test_with_yields_components(args, assert)
  world = Drecs::World.new
  id = world.spawn(SinglePosition.new(5, 6), SingleVelocity.new(7, 8))

  called = false
  result = world.with(id, SinglePosition, SingleVelocity) do |pos, vel|
    called = true
    assert.equal! pos.x, 5
    assert.equal! vel.dy, 8
  end

  assert.equal! called, true
  assert.equal! result, true
end


def test_with_returns_nil_when_missing(args, assert)
  world = Drecs::World.new
  id = world.spawn(SinglePosition.new(5, 6))

  result = world.with(id, SinglePosition, SingleVelocity)
  assert.equal! result, nil
end
