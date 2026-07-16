# MovementSystem - updates positions based on velocities
# This system showcases: high-performance query batch processing,
#                       in-place component modification, and bounds checking
class MovementSystem
  def call(world, args)
    # Cache the grid dimensions from args for bounds checking
    grid_w = args.grid.w
    grid_h = args.grid.h

    # Use query for high-performance batch iteration
    world.each_chunk(Position, Velocity) do |entity_ids, positions, velocities|
      i = 0
      len = entity_ids.length
      while i < len
        pos = positions[i]
        vel = velocities[i]

        # Update position
        pos.x += vel.dx
        pos.y += vel.dy

        # Wrap around screen edges (classic dungeon style)
        if pos.x < 0
          pos.x = grid_w
        elsif pos.x > grid_w
          pos.x = 0
        end

        if pos.y < 0
          pos.y = grid_h
        elsif pos.y > grid_h
          pos.y = 0
        end

        i += 1
      end
    end
  end
end