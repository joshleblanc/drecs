# RenderSystem - renders all entities to the screen
# Renders dungeon tiles, player (from PlayerGrid), and enemies
class RenderSystem
  def call(world, args)
    # Clear screen
    args.outputs.solids << { x: 0, y: 0, w: args.grid.w, h: args.grid.h, r: 20, g: 20, b: 30 }

    # Render dungeon tiles from dungeon resource
    render_dungeon(world, args)

    # Render player from PlayerGrid component
    render_player(world, args)

    # Render enemies from Position/Sprite (pixel coordinates)
    render_enemies(world, args)

    # Render items (gold, potions, stairs)
    render_items(world, args)

    # Render UI overlay
    render_ui(world, args)
  end

  private

  # Render dungeon tiles from dungeon data array
  def render_dungeon(world, args)
    dungeon = world.resource(:dungeon)
    return unless dungeon && dungeon[:dungeon]

    dungeon_data = dungeon[:dungeon]
    tile_size = dungeon[:tile_size] || 32

    y = 0
    while y < dungeon_data.length
      x = 0
      while x < dungeon_data[y].length
        tile_type = dungeon_data[y][x]
        color = Tile.color_for_type(tile_type)

        args.outputs.solids << {
          x: x * tile_size,
          y: y * tile_size,
          w: tile_size,
          h: tile_size,
          r: color[:r],
          g: color[:g],
          b: color[:b]
        }

        x += 1
      end
      y += 1
    end
  end

  # Render player from PlayerGrid component (grid coords to pixel)
  def render_player(world, args)
    world.each_entity(PlayerGrid, Health) do |entity_id, player_grid, health|
      # Convert grid position to pixel position (centered in tile)
      pos = player_grid.to_pixel_centered
      tile_size = PlayerGrid::TILE_SIZE

      # Player sprite (28x28 centered)
      player_size = 28
      args.outputs.solids << {
        x: pos[:x] - player_size / 2,
        y: pos[:y] - player_size / 2,
        w: player_size,
        h: player_size,
        r: 74,   # #4A90D9 blue
        g: 144,
        b: 217
      }

      # Draw direction indicator (small triangle in facing direction)
      draw_direction_indicator(args, pos, player_grid.facing)

      # Health bar
      bar_width = 40
      bar_height = 4
      bar_x = pos[:x] - bar_width / 2
      bar_y = pos[:y] + tile_size / 2 + 4

      # Background
      args.outputs.solids << {
        x: bar_x, y: bar_y, w: bar_width, h: bar_height,
        r: 80, g: 20, b: 20
      }

      # Health fill
      health_percent = health.current.to_f / health.max
      args.outputs.solids << {
        x: bar_x, y: bar_y, w: bar_width * health_percent, h: bar_height,
        r: 50, g: 200, b: 50
      }
    end
  end

  # Draw small indicator showing player facing direction
  def draw_direction_indicator(args, pos, facing)
    indicator_size = 6
    color = { r: 255, g: 255, b: 255 }

    case facing
    when :up
      args.outputs.solids << {
        x: pos[:x] - indicator_size / 2,
        y: pos[:y] + 10,
        w: indicator_size,
        h: indicator_size,
        r: color[:r], g: color[:g], b: color[:b]
      }
    when :down
      args.outputs.solids << {
        x: pos[:x] - indicator_size / 2,
        y: pos[:y] - 10 - indicator_size,
        w: indicator_size,
        h: indicator_size,
        r: color[:r], g: color[:g], b: color[:b]
      }
    when :left
      args.outputs.solids << {
        x: pos[:x] + 10,
        y: pos[:y] - indicator_size / 2,
        w: indicator_size,
        h: indicator_size,
        r: color[:r], g: color[:g], b: color[:b]
      }
    when :right
      args.outputs.solids << {
        x: pos[:x] - 10 - indicator_size,
        y: pos[:y] - indicator_size / 2,
        w: indicator_size,
        h: indicator_size,
        r: color[:r], g: color[:g], b: color[:b]
      }
    end
  end

  # Render enemies from Position/Sprite (pixel coordinates)
  def render_enemies(world, args)
    world.each_chunk(Position, Sprite, Enemy) do |entity_ids, positions, sprites, _enemies|
      i = 0
      len = entity_ids.length
      while i < len
        pos = positions[i]
        sprite = sprites[i]

        # Draw enemy sprite
        args.outputs.solids << {
          x: pos.x - sprite.w / 2,
          y: pos.y - sprite.h / 2,
          w: sprite.w,
          h: sprite.h,
          r: sprite.r,
          g: sprite.g,
          b: sprite.b
        }

        i += 1
      end
    end

    # Render enemy health bars
    world.each_chunk(Position, Health, Enemy) do |entity_ids, positions, healths, _enemies|
      i = 0
      len = entity_ids.length
      while i < len
        pos = positions[i]
        health = healths[i]

        bar_width = 30
        bar_height = 3
        bar_x = pos.x - bar_width / 2
        bar_y = pos.y + 20

        args.outputs.solids << {
          x: bar_x, y: bar_y, w: bar_width, h: bar_height,
          r: 80, g: 20, b: 20
        }

        health_percent = health.current.to_f / health.max
        args.outputs.solids << {
          x: bar_x, y: bar_y, w: bar_width * health_percent, h: bar_height,
          r: 200, g: 50, b: 50
        }

        i += 1
      end
    end
  end

  # Render items (gold, potions, stairs)
  def render_items(world, args)
    world.each_chunk(Position, Sprite, Item) do |entity_ids, positions, sprites, items|
      i = 0
      len = entity_ids.length
      while i < len
        pos = positions[i]
        sprite = sprites[i]
        item = items[i]

        # Gold sparkle effect
        if item.type == :gold
          args.outputs.solids << {
            x: pos.x - sprite.w / 2,
            y: pos.y - sprite.h / 2,
            w: sprite.w,
            h: sprite.h,
            r: 255,
            g: 215,
            b: 0
          }
        elsif item.type == :potion
          args.outputs.solids << {
            x: pos.x - sprite.w / 2,
            y: pos.y - sprite.h / 2,
            w: sprite.w,
            h: sprite.h,
            r: 255,
            g: 100,
            b: 100
          }
        elsif item.type == :stairs_up
          args.outputs.solids << {
            x: pos.x - sprite.w / 2,
            y: pos.y - sprite.h / 2,
            w: sprite.w,
            h: sprite.h,
            r: 100,
            g: 149,
            b: 237
          }
        end

        i += 1
      end
    end
  end

  # Render UI overlay
  def render_ui(world, args)
    game_state = world.resource(:game_state)
    turn_state = world.resource(:turn_state)
    dungeon = world.resource(:dungeon)

    # Floor indicator
    if dungeon && dungeon[:floor]
      args.outputs.labels << {
        x: 20,
        y: args.grid.h - 20,
        text: "Floor #{dungeon[:floor]}",
        size_enum: 3,
        alignment_enum: 0,
        r: 200,
        g: 200,
        b: 200
      }
    end

    # Turn indicator
    if turn_state
      turn_text = case turn_state[:phase]
                  when :player_input then "Your Turn - Move (WASD) / Space (Attack/Pickup)"
                  when :enemy_turn then "Enemy Turn..."
                  else turn_state[:phase].to_s
                  end

      args.outputs.labels << {
        x: args.grid.w / 2,
        y: args.grid.h - 30,
        text: turn_text,
        size_enum: 3,
        alignment_enum: 1,
        r: 200,
        g: 200,
        b: 200
      }
    end

    # Score display
    if game_state
      args.outputs.labels << {
        x: args.grid.w - 20,
        y: args.grid.h - 20,
        text: "Gold: #{game_state[:score] || 0}",
        size_enum: 3,
        alignment_enum: 2,
        r: 255,
        g: 215,
        b: 0
      }
    end

    # Game over screen
    if game_state && game_state[:game_over]
      args.outputs.solids << {
        x: args.grid.w / 2 - 150,
        y: args.grid.h / 2 - 60,
        w: 300,
        h: 120,
        r: 0,
        g: 0,
        b: 0,
        a: 220
      }

      args.outputs.labels << {
        x: args.grid.w / 2,
        y: args.grid.h / 2 + 20,
        text: "GAME OVER",
        size_enum: 6,
        alignment_enum: 1,
        r: 255,
        g: 50,
        b: 50
      }

      args.outputs.labels << {
        x: args.grid.w / 2,
        y: args.grid.h / 2 - 20,
        text: "Final Score: #{game_state[:score] || 0}",
        size_enum: 3,
        alignment_enum: 1,
        r: 255,
        g: 255,
        b: 255
      }

      args.outputs.labels << {
        x: args.grid.w / 2,
        y: args.grid.h / 2 - 50,
        text: "Press R to restart",
        size_enum: 2,
        alignment_enum: 1,
        r: 200,
        g: 200,
        b: 200
      }
    end

    # Controls hint
    args.outputs.labels << {
      x: 20,
      y: 30,
      text: "WASD: Move | Space: Attack/Pickup | R: Restart",
      size_enum: 2,
      r: 150,
      g: 150,
      b: 150
    }
  end
end