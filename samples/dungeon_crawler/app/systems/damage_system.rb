# DamageSystem - processes damage and death events
class DamageSystem
  def call(world, args)
    # Find player entity ID once
    player_id = nil
    world.each_entity(PlayerGrid) do |eid, _pg|
      player_id = eid
    end

    # Collect entities to destroy
    to_destroy = []

    # Process all DamageEvent events in queue
    world.each_event(DamageEvent) do |event|
      target_id = event.target_id
      damage = event.amount

      # Find the entity with target_id and apply damage using query
      world.each_entity(Health) do |entity_id, health|
        if entity_id == target_id
          health.current = [health.current - damage, 0].max
          
          entity_name = world.name(entity_id) || entity_id
          puts "Damage: #{damage} to #{entity_name}, HP: #{health.current}/#{health.max}"

          # Check if entity is dead (HP <= 0)
          if health.current <= 0
            to_destroy << target_id
          end
        end
      end
    end

    # Send DeathEvent for entities being destroyed
    to_destroy.each do |entity_id|
      entity_name = world.name(entity_id) || entity_id
      puts "#{entity_name} killed!"
      world.send_event(DeathEvent.new(entity_id, player_id || 0))
      
      # Mark for destruction
      world.add_component(entity_id, Destroyed.new)
    end

    # Clear processed events
    world.clear_events!(DamageEvent)
    world.clear_events!(DeathEvent)
  end
end