require 'lib/drecs.rb'

class Position < Struct.new(:x, :y); end

def test_query_ergonomics(args, assert)
  world = Drecs::World.new
  id = world.spawn(Position.new(10, 20))
  
  # Current behavior (SoA chunk) check
  # If we haven't changed it yet, this might fail if I assert the NEW behavior.
  # So let's assert the NEW desired behavior to confirm failure first?
  # Or just verify what happens.
  
  res = world.query(Position).first
  # We want res to be [id, position], not [[id], [position]]
  
  # Determine if it's the old or new behavior
  if res[0].is_a?(Array)
    puts "Current behavior: query().first returns Arrays (SoA)"
    # assert.fail! "query().first returned SoA arrays, expected [id, component]"
  else
    puts "New behavior: query().first returns Entity (AoS)"
  end
  
  # Check standard block behavior (must remain SoA)
  world.query(Position) do |ids, positions|
    assert.true! ids.is_a?(Array), "Block yield 1 (ids) should be Array"
    assert.true! positions.is_a?(Array), "Block yield 2 (positions) should be Array"
  end
end
