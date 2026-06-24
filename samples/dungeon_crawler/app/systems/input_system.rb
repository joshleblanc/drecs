# InputSystem - handles player keyboard input
# This system showcases: single-entity access via each_entity with Player/Position/Velocity
class InputSystem
  def call(world, args)
    kb = args.inputs.keyboard

    # Use each_entity to get the player with multiple components
    world.each_entity(Player, Position, Velocity) do |entity_id, player, pos, vel|
      dx = 0
      dy = 0

      # Movement input
      dx -= 1 if kb.left || kb.a
      dx += 1 if kb.right || kb.d
      dy += 1 if kb.up || kb.w
      dy -= 1 if kb.down || kb.s

      # Normalize diagonal movement
      if dx != 0 && dy != 0
        dx *= 0.707
        dy *= 0.707
      end

      # Apply movement
      vel.dx = dx * player.speed
      vel.dy = dy * player.speed

      # Mark velocity as changed for the change detection system
      world.set_component(entity_id, vel)
    end
  end
end