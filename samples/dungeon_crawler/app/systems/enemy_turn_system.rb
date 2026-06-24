# EnemyTurnSystem - processes all enemy actions after player acts
# Enemies chase the player and attack if adjacent
class EnemyTurnSystem
  def call(world, args)
    turn_state = world.resource(:turn_state)

    # Only run during enemy_turn phase
    return unless turn_state && turn_state[:phase] == :enemy_turn

    # Process each enemy - simple chase AI
    process_enemies(world)

    # Mark enemies as having acted
    turn_state[:enemy_acted] = true
  end

  def process_enemies(world)
    player = nil
    world.each_entity(PlayerGrid) do |entity_id, player_grid|
      player = player_grid
    end
    return unless player

    world.each_entity(Enemy, Position, Health) do |entity_id, enemy, pos, health|
      next if health.current <= 0  # Skip dead enemies

      # Get enemy grid position
      enemy_grid_x = (pos.x / 32).to_i
      enemy_grid_y = (pos.y / 32).to_i

      # Simple chase: move one tile toward player
      dx = player.grid_x - enemy_grid_x
      dy = player.grid_y - enemy_grid_y

      if dx == 0 && dy == 0
        # Adjacent - attack player
        player_health = nil
        world.each_entity(PlayerGrid, Health) do |pid, pg, ph|
          player_health = ph
        end
        if player_health
          player_health.current = [player_health.current - enemy.damage, 0].max
          puts "Goblin attacks! Player HP: #{player_health.current}"
        end
      elsif dx.abs >= dy.abs && dx != 0
        # Move horizontally
        new_x = enemy_grid_x + (dx > 0 ? 1 : -1)
        if can_move_to?(world, new_x, enemy_grid_y) && !tile_occupied?(world, new_x, enemy_grid_y, entity_id)
          pos.x = new_x * 32 + 16  # Center in tile
        end
      elsif dy != 0
        # Move vertically
        new_y = enemy_grid_y + (dy > 0 ? 1 : -1)
        if can_move_to?(world, enemy_grid_x, new_y) && !tile_occupied?(world, enemy_grid_x, new_y, entity_id)
          pos.y = new_y * 32 + 16  # Center in tile
        end
      end
    end
  end

  def can_move_to?(world, x, y)
    dungeon = world.resource(:dungeon)
    return false unless dungeon && dungeon[:dungeon]
    dungeon_data = dungeon[:dungeon]
    return false if x < 0 || y < 0 || y >= dungeon_data.length || x >= dungeon_data[0].length
    tile_type = dungeon_data[y][x]
    tile_type == Tile::TILE_FLOOR
  end

  def tile_occupied?(world, x, y, exclude_entity)
    # Check other enemies
    world.each_entity(Enemy, Position) do |eid, _e, p|
      next if eid == exclude_entity
      px = (p.x / 32).to_i
      py = (p.y / 32).to_i
      return true if px == x && py == y
    end
    # Check player
    world.each_entity(PlayerGrid) do |pid, pg|
      return true if pg.grid_x == x && pg.grid_y == y
    end
    false
  end
end