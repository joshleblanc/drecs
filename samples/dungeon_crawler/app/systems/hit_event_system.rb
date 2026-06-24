# HitEventSystem - processes hit events and applies damage
# This system showcases: event system (each_event), event clearing,
#                       and batch destruction with deferred mutations
class HitEventSystem
  def call(world, args)
    to_damage = []
    to_destroy_enemies = []
    to_spawn_loot = []

    # Process all HitEvents
    world.each_event(HitEvent) do |event|
      damage = event.damage
      target_id = event.target_id

      # Apply damage to target
      if world.has_component?(target_id, Health)
        health = world.get_component(target_id, Health)
        health.hurt(damage)
        world.set_component(target_id, health)

        # Send damage event for UI/gameplay feedback
        world.send_event(DamageEvent.new(target_id, damage, :projectile))

        # Check if target died
        if health.dead?
          if world.has_component?(target_id, Enemy)
            # Enemy died - schedule for destruction and loot spawning
            pos = world.get_component(target_id, Position)
            to_destroy_enemies << target_id
            to_spawn_loot << { x: pos.x, y: pos.y, value: 10 } if pos
            world.send_event(DeathEvent.new(target_id, event.projectile_id))
          elsif world.has_component?(target_id, Player)
            # Player died - will be handled by game over logic
          end
        end
      end
    end

    # Process death events for cleanup
    world.each_event(DeathEvent) do |event|
      # Could trigger animations, sound effects, etc. via events
    end

    # Batch destroy enemies
    unless to_destroy_enemies.empty?
      world.commands { |cmd| cmd.destroy(*to_destroy_enemies) }
    end

    # Spawn loot at enemy positions
    to_spawn_loot.each do |loot_data|
      world.spawn(
        Position.new(loot_data[:x], loot_data[:y]),
        Collider.new(12),
        Sprite.new(16, 16, 255, 215, 0),
        Loot.new(loot_data[:value]),
        Lifetime.new(300)  # Loot disappears after 5 seconds
      )
    end

    # Clear processed events
    world.clear_events!(HitEvent)
    world.clear_events!(DeathEvent)
  end
end