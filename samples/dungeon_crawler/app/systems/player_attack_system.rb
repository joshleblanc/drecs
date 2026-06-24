# PlayerAttackSystem - handles grid-based melee attack
# Attack in facing direction with Space key
# This system showcases: melee combat, directional attacks, damage events
class PlayerAttackSystem
  def call(world, args)
    return unless args.inputs.keyboard.key_down.space

    world.each_entity(PlayerGrid) do |entity_id, player_grid|
      # Get target tile in facing direction
      target = player_grid.target_tile

      # Send MeleeAttackEvent with 99 damage (instant kill for goblins with 3HP per spec)
      world.send_event(MeleeAttackEvent.new(entity_id, target[:x], target[:y], 99))

      # Check for enemy at target tile and deal damage directly
      world.each_entity(Enemy, Position) do |enemy_id, enemy, pos|
        # Convert enemy position to tile coords
        tile_x = (pos.x / 32).to_i
        tile_y = (pos.y / 32).to_i

        # Check if enemy is in target tile
        if tile_x == target[:x] && tile_y == target[:y]
          # Enemy hit! Send DamageEvent with 99 damage
          world.send_event(DamageEvent.new(enemy_id, 99, entity_id))
          puts "Player attacks #{world.name(enemy_id)} for 99 damage!"

          # Mark player as having acted this turn
          turn_state = world.resource(:turn_state)
          turn_state[:player_acted] = true if turn_state
        end
      end
    end
  end
end