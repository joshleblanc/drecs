# GridMovementSystem - handles grid-based player movement
# Player snaps to tiles (32x32) and moves exactly one tile per key press
# Checks tile types in dungeon resource to prevent moving into walls
class GridMovementSystem
  def call(world, args)
    kb = args.inputs.keyboard

    # Only process input on key down (not held)
    return unless any_key_pressed?(kb)

    world.each_entity(PlayerGrid) do |entity_id, player_grid|
      direction = get_movement_direction(kb)

      if direction
        # Update facing direction even if we can't move
        player_grid.facing = direction

        # Calculate target position
        target = player_grid.target_tile

        # Check if movement is valid (within bounds and not a wall)
        if can_move_to?(world, target[:x], target[:y])
          # Move the player (moves one tile in direction)
          player_grid.move_toward(direction)
          
          # Mark player as having acted this turn
          turn_state = world.resource(:turn_state)
          turn_state[:player_acted] = true if turn_state
        end
      end
    end
  end

  private

  # Check if any movement key was just pressed
  def any_key_pressed?(kb)
    kb.key_down.up || kb.key_down.down || kb.key_down.left || kb.key_down.right ||
    kb.key_down.w || kb.key_down.a || kb.key_down.s || kb.key_down.d
  end

  # Get movement direction from keyboard input
  # Returns direction symbol or nil if no direction pressed
  def get_movement_direction(kb)
    if kb.key_down.up || kb.key_down.w
      :up
    elsif kb.key_down.down || kb.key_down.s
      :down
    elsif kb.key_down.left || kb.key_down.a
      :left
    elsif kb.key_down.right || kb.key_down.d
      :right
    end
  end

  # Check if the target tile is walkable using dungeon resource
  def can_move_to?(world, x, y)
    dungeon = world.resource(:dungeon)
    return false unless dungeon && dungeon[:dungeon]

    dungeon_data = dungeon[:dungeon]

    # Check bounds
    return false if x < 0 || y < 0 || y >= dungeon_data.length || x >= dungeon_data[0].length

    # Get tile type at position (0 = floor, 1 = wall, etc.)
    tile_type = dungeon_data[y][x]

    # Only floors are walkable
    return false unless tile_type == Tile::TILE_FLOOR
    
    # Check if enemy is on target tile
    world.each_entity(Enemy, Position) do |eid, _e, pos|
      enemy_x = (pos.x / 32).to_i
      enemy_y = (pos.y / 32).to_i
      return false if enemy_x == x && enemy_y == y
    end
    
    true
  end
end