class PlayerInputSystem
  def call(world, args)
    world.each_entity(Player, Rotation, Velocity, Position) do |entity_id, player, rotation, velocity, position|
      if args.inputs.keyboard.key_held.left
        rotation.angular_velocity = -player.rotation_speed
      elsif args.inputs.keyboard.key_held.right
        rotation.angular_velocity = player.rotation_speed
      else
        rotation.angular_velocity = 0
      end

      if args.inputs.keyboard.key_held.up
        angle_rad = rotation.angle * Math::PI / 180
        velocity.dx += Math.cos(angle_rad) * player.thrust_power
        velocity.dy += Math.sin(angle_rad) * player.thrust_power

        max_speed = 8
        speed = Math.sqrt(velocity.dx ** 2 + velocity.dy ** 2)
        if speed > max_speed
          velocity.dx = (velocity.dx / speed) * max_speed
          velocity.dy = (velocity.dy / speed) * max_speed
        end
      end

      if args.inputs.keyboard.key_down.space
        spawn_bullet(world, position, rotation, velocity)
      end
    end
  end

  private

  def spawn_bullet(world, player_pos, player_rotation, player_vel)
    angle_rad = player_rotation.angle * Math::PI / 180
    bullet_speed = 12

    world.spawn(
      Position.new(player_pos.x, player_pos.y),
      Velocity.new(
        Math.cos(angle_rad) * bullet_speed + player_vel.dx,
        Math.sin(angle_rad) * bullet_speed + player_vel.dy
      ),
      Collider.new(2),
      Bullet.new(60)
    )
  end
end
