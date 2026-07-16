# PickupSystem - handles player picking up items
# Gold adds to score, potions heal, stairs change floors
class PickupSystem
  def call(world, args)
    return unless args.inputs.keyboard.key_down.space

    player_pos = nil
    player_health = nil
    world.each_entity(PlayerGrid, Health) do |eid, pg, health|
      player_pos = pg
      player_health = health
    end
    return unless player_pos

    # Track items to destroy after iteration
    items_to_destroy = []

    # Check for items at player position using query with entity_ids
    world.each_chunk(Item, Position) do |entity_ids, items, positions|
      i = 0
      len = items.length
      while i < len
        item = items[i]
        pos = positions[i]
        entity_id = entity_ids[i]
        next unless pos

        item_tile_x = (pos.x / 32).to_i
        item_tile_y = (pos.y / 32).to_i

        # Check if player is on the same tile
        if item_tile_x == player_pos.grid_x && item_tile_y == player_pos.grid_y
          case item.type
          when :gold
            game_state = world.resource(:game_state)
            game_state[:score] = (game_state[:score] || 0) + item.value
            puts "Picked up #{item.value} gold! Total: #{game_state[:score]}"
            items_to_destroy << entity_id
            
          when :potion
            if player_health
              player_health.current = [player_health.current + item.value, player_health.max].min
              puts "Drank potion! HP: #{player_health.current}/#{player_health.max}"
            end
            items_to_destroy << entity_id
            
          when :stairs_up
            puts "Climbed stairs!"
            items_to_destroy << entity_id
          end
        end

        i += 1
      end
    end

    # Destroy collected items
    items_to_destroy.each do |item_id|
      world.destroy(item_id) if world.entity_exists?(item_id)
    end
  end
end