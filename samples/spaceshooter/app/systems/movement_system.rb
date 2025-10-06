class MovementSystem
  def call(world, args)
    world.each_entity(Position, Velocity) do |entity_id, pos, vel|
      pos.x += vel.x
      pos.y += vel.y
    end
  end
end
