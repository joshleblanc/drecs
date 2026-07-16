# LootSystem - handles player collecting loot
# This system showcases: query filters, single-entity access, and resource management
class LootSystem
  def call(world, args)
    world.each_entity(Player, Position) do |player_id, _player, player_pos|
      world.each_chunk(Position, Loot, Collider) do |entity_ids, positions, _loots, colliders|
        i = 0
        len = entity_ids.length
        loot_collected = []

        while i < len
          loot_id = entity_ids[i]
          loot_pos = positions[i]
          loot_coll = colliders[i]

          dx = player_pos.x - loot_pos.x
          dy = player_pos.y - loot_pos.y
          dist = Math.sqrt(dx * dx + dy * dy)

          if dist < 20 + loot_coll.radius
            loot_collected << loot_id
          end

          i += 1
        end

        unless loot_collected.empty?
          # Calculate total value
          total_value = 0
          loot_collected.each do |loot_id|
            loot = world.get_component(loot_id, Loot)
            total_value += loot.value if loot
          end

          # Update score resource
          if world.resource(:score)
            score = world.resource(:score)
            score[:value] += total_value
          end

          # Send loot collected event
          world.send_event(LootCollectedEvent.new(loot_collected[0], player_id, total_value))

          # Destroy collected loot
          world.commands { |cmd| cmd.destroy(*loot_collected) }
        end
      end
    end
  end
end