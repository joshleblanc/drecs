require 'lib/drecs.rb'

class Position < Struct.new(:x, :y); end

def test_spawn_many_unique(args, assert)
  world = Drecs::World.new
  
  # Spawn 2 entities with a Position component
  ids = world.spawn_many(2, Position.new(0, 0))
  
  id1 = ids[0]
  id2 = ids[1]
  
  pos1 = world.get_component(id1, Position)
  pos2 = world.get_component(id2, Position)
  
  # Assert they are not the same object
  assert.false! pos1.equal?(pos2), "Components shared the same reference!"
  
  # Assert modifying one doesn't affect the other
  pos1.x = 100
  assert.equal! pos2.x, 0, "Modifying one component affected the other!"
end
