class RenderSystem
  def call(world, args)
    args.outputs.solids << { x: 0, y: 0, w: 1280, h: 720, r: 0, g: 0, b: 0 }

    world.each_entity(Position, Polygon, Rotation) do |entity_id, pos, polygon, rotation|
      transformed_points = polygon.points.map do |px, py|
        angle_rad = rotation.angle * Math::PI / 180
        rx = px * Math.cos(angle_rad) - py * Math.sin(angle_rad)
        ry = px * Math.sin(angle_rad) + py * Math.cos(angle_rad)
        [pos.x + rx, pos.y + ry]
      end

      (0...transformed_points.length).each do |i|
        x1, y1 = transformed_points[i]
        x2, y2 = transformed_points[(i + 1) % transformed_points.length]

        args.outputs.lines << {
          x: x1, y: y1, x2: x2, y2: y2,
          r: polygon.r, g: polygon.g, b: polygon.b
        }
      end
    end

    world.each_entity(Bullet, Position) do |entity_id, bullet, pos|
      args.outputs.solids << {
        x: pos.x - 2, y: pos.y - 2, w: 4, h: 4,
        r: 255, g: 255, b: 0
      }
    end

    args.outputs.labels << {
      x: 10, y: 710,
      text: "Score: #{args.state.score || 0}",
      size_enum: 4,
      r: 255, g: 255, b: 255
    }

    asteroids_count = world.count(Asteroid)
    args.outputs.labels << {
      x: 10, y: 670,
      text: "Asteroids: #{asteroids_count}",
      size_enum: 2,
      r: 200, g: 200, b: 200
    }

    args.outputs.labels << {
      x: 10, y: 640,
      text: "Hooks: Asteroids +#{args.state.hook_asteroids_spawned}/-#{args.state.hook_asteroids_removed} | Bullets -#{args.state.hook_bullets_removed}",
      size_enum: 2,
      r: 180, g: 180, b: 180
    }

    if args.state.game_over
      args.outputs.solids << {
        x: 0, y: 0, w: 1280, h: 720,
        r: 0, g: 0, b: 0, a: 180
      }

      args.outputs.labels << {
        x: 640, y: 400,
        text: "GAME OVER",
        size_enum: 10,
        alignment_enum: 1,
        r: 255, g: 0, b: 0
      }

      args.outputs.labels << {
        x: 640, y: 340,
        text: "Score: #{args.state.score || 0}",
        size_enum: 6,
        alignment_enum: 1,
        r: 255, g: 255, b: 255
      }

      args.outputs.labels << {
        x: 640, y: 280,
        text: "Press R to restart",
        size_enum: 4,
        alignment_enum: 1,
        r: 200, g: 200, b: 200
      }
    end
  end
end
