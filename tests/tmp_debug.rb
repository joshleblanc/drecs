require 'lib/drecs.rb'

def test_debug_remove_all(args, assert)
  world = Drecs::World.new
  e1 = world.spawn({ position: { x: 1, y: 2 }, velocity: { dx: 1, dy: 1 } })
  e2 = world.spawn({ position: { x: 3, y: 4 }, velocity: { dx: 2, dy: 2 } })
  e3 = world.spawn({ position: { x: 5, y: 6 } })

  q = world.query(:velocity)
  collected = q.flat_map { |*a| a.first }
  puts "DEBUG collected=#{collected.inspect}"

  entities_via_each = []
  world.query(:velocity).each { |*a| entities_via_each << a.inspect }
  puts "DEBUG each yields=#{entities_via_each.inspect}"

  world.remove_all(:velocity)
  puts "DEBUG count after remove_all=#{world.count(:position, :velocity)}"
  world.each_entity(:position) do |id, _pos|
    puts "DEBUG entity #{id} has velocity=#{world.has_component?(id, :velocity)}"
  end
  assert.true! true
end
