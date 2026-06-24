# EnemyAISystem - handles enemy movement and targeting
# This system showcases: query filters (with:, any:), multiple archetype access,
#                       change detection (changed:), and single-entity access (get_many)
#
# NOTE: Enemy AI logic is stubbed out for now. This system processes enemies
#       during enemy turn, but actual AI behavior is deferred to a separate task.
class EnemyAISystem
  def call(world, args)
    # Only process during enemy turn
    turn_state = world.resource(:turn_state)
    return unless turn_state && turn_state[:phase] == :enemy_turn

    # Find player position for enemy targeting
    player_pos = nil
    world.each_entity(Player, Position) do |entity_id, _player, pos|
      player_pos = pos
    end

    # Query for enemies - showcases 'with:' filter to require additional components
    world.each_entity(Enemy, Position, Velocity, with: Health) do |entity_id, enemy, pos, vel|
      if player_pos
        dx = player_pos.x - pos.x
        dy = player_pos.y - pos.y
        dist = Math.sqrt(dx * dx + dy * dy)

        if dist < enemy.detection_range && dist > 0
          # Move toward player
          vel.dx = (dx / dist) * 2
          vel.dy = (dy / dist) * 2
        else
          # Wander if no player detected
          vel.dx = (rand - 0.5) * 2
          vel.dy = (rand - 0.5) * 2
        end

        world.set_component(entity_id, vel)
      end
    end

    # Also handle enemies without health (different archetype!)
    world.each_entity(Enemy, Position, Velocity, without: Health) do |entity_id, enemy, pos, vel|
      # Wandering behavior for enemies without health (invincible enemies)
      vel.dx = (rand - 0.5) * 1.5
      vel.dy = (rand - 0.5) * 1.5
      world.set_component(entity_id, vel)
    end

    # NOTE: In the new phase-based system, EnemyTurnSystem sets enemy_acted
    # instead of EnemyAISystem. This system only handles movement/AI decisions.
  end
end