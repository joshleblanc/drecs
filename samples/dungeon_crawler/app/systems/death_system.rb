# DeathSystem - handles player death and game over
class DeathSystem
  def call(world, args)
    # Check if player is dead
    world.each_entity(PlayerGrid, Health) do |entity_id, _player, health|
      if health.current <= 0
        # Mark game over in state resource
        state = world.resource(:game_state)
        state[:game_over] = true
        puts "Game Over!"
      end
    end

    # Process loot collected events
    world.each_event(LootCollectedEvent) do |event|
      # Score update could go here
    end
    world.clear_events!(LootCollectedEvent)

    # Process damage events
    world.each_event(DamageEvent) do |event|
      # Could trigger damage numbers, screen shake, etc.
    end
    world.clear_events!(DamageEvent)
  end
end