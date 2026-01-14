class PlayerInputSystem
  BULLET_BUNDLE = Drecs.bundle(Position, Velocity, Sprite, Bullet, Lifetime)

  def call(world, args)
    world.each_entity(Player, Position, Velocity) do |entity_id, player, pos, vel|
      vel.x = 0
      vel.y = 0

      if args.inputs.keyboard.left || args.inputs.keyboard.a
        vel.x = -player.speed
      elsif args.inputs.keyboard.right || args.inputs.keyboard.d
        vel.x = player.speed
      end

      if args.inputs.keyboard.up || args.inputs.keyboard.w
        vel.y = player.speed
      elsif args.inputs.keyboard.down || args.inputs.keyboard.s
        vel.y = -player.speed
      end

      if player.fire_cooldown > 0
        player.fire_cooldown -= 1
      end

      if args.inputs.keyboard.space && player.fire_cooldown <= 0
        spawn_bullet(world, pos.x, pos.y + 20)
        player.fire_cooldown = 15
      end
    end
  end

  private

  def spawn_bullet(world, x, y)
    world.spawn_bundle(BULLET_BUNDLE,
      Position.new(x, y),
      Velocity.new(0, 10),
      Sprite.new(4, 12, 255, 255, 0),
      Bullet.new(1),
      Lifetime.new(120)
    )
  end
end
