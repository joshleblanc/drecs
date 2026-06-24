# CombatSystem - handles player melee attacks
# This system showcases: query with filters, adjacent tile detection,
#                       and damage application via events
class CombatSystem
  def call(world, args)
    kb = args.inputs.keyboard

    # Only process during player input phase
    turn_state = world.resource(:turn_state)
    return unless turn_state && turn_state[:phase] == :player_input

    world.each_entity(Player, Position) do |entity_id, player, pos|
      # Check attack cooldown
      player.attack_cooldown = [player.attack_cooldown - 1, 0].max
      world.set_component(entity_id, player)

      # Attack on spacebar (only on key down, not hold)
      if kb.key_down.space && player.attack_cooldown == 0
        player.attack_cooldown = 20  # Cooldown in frames
        world.set_component(entity_id, player)

        # Get attack direction from player's facing direction
        facing = player.facing_vector
        target_x = pos.x + facing[:dx]
        target_y = pos.y + facing[:dy]

        # Attack damage
        damage = 25

        # Find enemies on the target tile
        world.each_entity(Enemy, Position, Health) do |enemy_id, enemy, enemy_pos, health|
          # Check if enemy is on adjacent tile (within 1 tile)
          dx = (enemy_pos.x - target_x).abs
          dy = (enemy_pos.y - target_y).abs

          if dx <= 1 && dy <= 1 && (dx + dy > 0)  # Adjacent and not same tile
            # Apply damage
            health.hurt(damage)
            world.set_component(enemy_id, health)

            # Send damage event
            world.send_event(DamageEvent.new(enemy_id, damage, :player_attack))
            world.send_event(AttackEvent.new(entity_id, enemy_id, damage))
          end
        end
      end
    end
  end
end