require 'lib/drecs.rb'

# Named-class component via the Drecs::Component mixin, with a custom
# initializer (defaults), instance methods, and a real class constant.
class CMVelocity
  include Drecs::Component
  component :dx, :dy

  def initialize(dx = 0, dy = 0)
    @dx = dx
    @dy = dy
  end

  def moving?
    dx != 0 || dy != 0
  end
end

class CMTile
  include Drecs::Component
  component :type

  TILE_FLOOR = 0

  def initialize(type = TILE_FLOOR)
    @type = type
  end

  def floor?
    type == TILE_FLOOR
  end
end

def test_component_mixin_accessors(args, assert)
  v = CMVelocity.new
  assert.equal! v.dx, 0, "default initializer should apply (dx)"
  assert.equal! v.dy, 0, "default initializer should apply (dy)"
  assert.equal! v.moving?, false, "instance methods should be available"

  v.dx = 3
  assert.equal! v.dx, 3, "setter should write through the @-ivar"
  assert.equal! v[:dx], 3, "[] reads the same @-ivar as the setter"
  assert.equal! v.moving?, true, "method should reflect mutated state"
end

def test_component_mixin_struct_api(args, assert)
  v = CMVelocity.new(1, 2)
  assert.equal! v.members, [:dx, :dy], "members reflects declared fields"
  assert.equal! v.values, [1, 2], "values returns fields in declaration order"
  v[:dy] = 9
  assert.equal! v.dy, 9, "[]= writes the same @-ivar as the accessor"
end

def test_component_mixin_class_constants(args, assert)
  # Unlike the class_eval block form, mixin constants are REAL class constants.
  assert.equal! CMTile::TILE_FLOOR, 0, "Tile::TILE_FLOOR must be a class constant"
  assert.equal! CMTile.new.floor?, true, "default type uses the class constant"
  assert.equal! CMTile.new(1).floor?, false
end

def test_component_mixin_not_a_struct(args, assert)
  # Native-system guard relies on mixin components NOT being Struct subclasses.
  assert.equal! CMVelocity.new.is_a?(Struct), false, "mixin component must not be a Struct"
end

def test_component_mixin_in_world(args, assert)
  world = Drecs::World.new
  id = world.spawn(CMVelocity.new(5, 7))

  found = false
  world.each_entity(CMVelocity) do |entity_id, vel|
    found = true
    assert.equal! entity_id, id
    assert.true! vel.is_a?(CMVelocity), "each_entity yields the mixin component"
    assert.equal! vel.dx, 5
  end
  assert.true! found, "spawned mixin component should be queryable"

  # Snapshot deep-copies via klass.new(*values); make sure that round-trips
  # and stays decoupled from later mutations of the live component.
  snap = world.snapshot
  snap_entry = snap[:entities].find { |eid, _comps| eid == id }
  snap_vel = snap_entry[1][CMVelocity]
  assert.equal! snap_vel.dx, 5, "snapshot should capture the live value"

  world.get_many(id, CMVelocity)[0].dx = 99
  assert.equal! snap_vel.dx, 5, "snapshot must decouple from live mutations"
end
