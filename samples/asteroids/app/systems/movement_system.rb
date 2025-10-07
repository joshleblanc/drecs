class MovementSystem
  def call(world, args)
    world.query(Position, Velocity) do |entity_ids, positions, velocities|
      positions.each_with_index do |pos, i|
        vel = velocities[i]
        pos.x += vel.dx
        pos.y += vel.dy

        pos.x = pos.x % 1280
        pos.y = pos.y % 720
      end
    end

    world.query(Rotation) do |entity_ids, rotations|
      rotations.each do |rotation|
        rotation.angle += rotation.angular_velocity
        rotation.angle = rotation.angle % 360
      end
    end

    world.query(Velocity) do |entity_ids, velocities|
      velocities.each do |vel|
        vel.dx *= 0.99
        vel.dy *= 0.99
      end
    end
  end
end
