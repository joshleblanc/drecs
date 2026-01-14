Position = Struct.new(:x, :y)
Velocity = Struct.new(:dx, :dy)
Size = Struct.new(:w, :h)
Color = Struct.new(:r, :g, :b)

Player = Struct.new(:speed)
Enemy = Struct.new(:speed)
Bullet = Struct.new(:ttl)
Frozen = Class.new

WORLD_W = 1280
WORLD_H = 720

def setup(args)
  world = Drecs::World.new

  args.state.render_cache = {}
  args.state.full_render = true
  args.state.to_remove_from_cache = []
  args.state.last_shot_at = 0
  args.state.game_over = false
  args.state.score = 0

  player_id = world.spawn(
    Position.new(WORLD_W / 2, WORLD_H / 2),
    Velocity.new(0, 0),
    Size.new(18, 18),
    Color.new(50, 220, 255),
    Player.new(5.0)
  )

  args.state.player_id = player_id

  spawn_enemies(world, 200)

  world
end

def spawn_enemies(world, count)
  i = 0
  while i < count
    world.spawn(
      Position.new(rand(WORLD_W), rand(WORLD_H)),
      Velocity.new(Numeric.rand(-2.0..2.0), Numeric.rand(-2.0..2.0)),
      Size.new(12, 12),
      Color.new(255, 80, 80),
      Enemy.new(2.0)
    )
    i += 1
  end
end

def tick(args)
  args.state.world ||= setup(args)
  world = args.state.world

  world.advance_change_tick!

  handle_input(args, world)
  update_bullets(args, world)
  move_entities(args, world)
  handle_collisions(args, world)
  update_render_cache(args, world)
  render(args, world)
end

def handle_input(args, world)
  player_id = args.state.player_id
  player_pos = world.get_component(player_id, Position)
  player_vel = world.get_component(player_id, Velocity)
  player = world.get_component(player_id, Player)

  dx = 0
  dy = 0

  kb = args.inputs.keyboard
  dx -= 1 if kb.left || kb.a
  dx += 1 if kb.right || kb.d
  dy += 1 if kb.up || kb.w
  dy -= 1 if kb.down || kb.s

  speed = player.speed
  player_vel.dx = dx * speed
  player_vel.dy = dy * speed

  world.set_component(player_id, player_vel)

  if args.inputs.mouse.click
    shoot(args, world, player_pos)
  end

  if kb.key_down.f
    toggle_freeze(args, world)
  end

  if kb.key_down.r
    args.state.world = setup(args)
  end
end

def shoot(args, world, player_pos)
  now = args.state.tick_count
  last = args.state.last_shot_at
  return if now - last < 6

  args.state.last_shot_at = now

  mx = args.inputs.mouse.x
  my = args.inputs.mouse.y

  dx = mx - player_pos.x
  dy = my - player_pos.y
  mag = Math.sqrt(dx * dx + dy * dy)
  mag = 1 if mag == 0

  speed = 9.0
  vx = dx / mag * speed
  vy = dy / mag * speed

  world.spawn(
    Position.new(player_pos.x, player_pos.y),
    Velocity.new(vx, vy),
    Size.new(6, 6),
    Color.new(255, 255, 120),
    Bullet.new(90)
  )
end

def toggle_freeze(args, world)
  to_freeze = []
  to_unfreeze = []

  world.each_entity(Enemy) do |entity_id, _enemy|
    if world.has_component?(entity_id, Frozen)
      to_unfreeze << entity_id
    else
      to_freeze << entity_id
    end
  end

  half = (to_freeze.length / 2.0).ceil
  i = 0
  while i < half
    world.add_component(to_freeze[i], Frozen.new)
    i += 1
  end

  i = 0
  while i < to_unfreeze.length
    world.remove_component(to_unfreeze[i], Frozen)
    i += 1
  end
end

def update_bullets(args, world)
  expired = []

  world.each_entity(Bullet) do |entity_id, bullet|
    bullet.ttl -= 1
    if bullet.ttl <= 0
      expired << entity_id
    else
      world.set_component(entity_id, bullet)
    end
  end

  unless expired.empty?
    world.destroy(*expired)
    args.state.to_remove_from_cache.concat(expired)
  end
end

def move_entities(args, world)
  world.each_entity(Position, Velocity, without: Frozen) do |entity_id, pos, vel|
    pos.x += vel.dx
    pos.y += vel.dy

    pos.x += WORLD_W if pos.x < 0
    pos.x -= WORLD_W if pos.x > WORLD_W
    pos.y += WORLD_H if pos.y < 0
    pos.y -= WORLD_H if pos.y > WORLD_H

    world.set_component(entity_id, pos)
  end
end

def handle_collisions(args, world)
  bullets = []
  world.query(Position, Size, any: [Bullet], changed: [Position]) do |entity_ids, positions, sizes|
    i = 0
    len = entity_ids.length
    while i < len
      bullets << [entity_ids[i], positions[i], sizes[i]]
      i += 1
    end
  end

  return if bullets.empty?

  enemies = []
  world.query(Position, Size, any: [Enemy]) do |entity_ids, positions, sizes|
    i = 0
    len = entity_ids.length
    while i < len
      enemies << [entity_ids[i], positions[i], sizes[i]]
      i += 1
    end
  end

  return if enemies.empty?

  bullets_to_destroy = []
  enemies_to_destroy = []

  bi = 0
  while bi < bullets.length
    b_id, b_pos, b_size = bullets[bi]

    ei = 0
    while ei < enemies.length
      e_id, e_pos, e_size = enemies[ei]

      if aabb_overlap?(b_pos, b_size, e_pos, e_size)
        bullets_to_destroy << b_id
        enemies_to_destroy << e_id
        break
      end

      ei += 1
    end

    bi += 1
  end

  unless bullets_to_destroy.empty?
    world.destroy(*bullets_to_destroy)
    args.state.to_remove_from_cache.concat(bullets_to_destroy)
  end

  unless enemies_to_destroy.empty?
    world.destroy(*enemies_to_destroy)
    args.state.to_remove_from_cache.concat(enemies_to_destroy)
    args.state.score += enemies_to_destroy.length

    spawn_enemies(world, enemies_to_destroy.length)
    args.state.full_render = true
  end
end

def aabb_overlap?(a_pos, a_size, b_pos, b_size)
  ax1 = a_pos.x - a_size.w / 2
  ay1 = a_pos.y - a_size.h / 2
  ax2 = ax1 + a_size.w
  ay2 = ay1 + a_size.h

  bx1 = b_pos.x - b_size.w / 2
  by1 = b_pos.y - b_size.h / 2
  bx2 = bx1 + b_size.w
  by2 = by1 + b_size.h

  ax1 < bx2 && ax2 > bx1 && ay1 < by2 && ay2 > by1
end

def update_render_cache(args, world)
  cache = args.state.render_cache

  unless args.state.to_remove_from_cache.empty?
    args.state.to_remove_from_cache.each { |id| cache.delete(id) }
    args.state.to_remove_from_cache.clear
  end

  tags = [Player, Enemy, Bullet]

  if args.state.full_render
    cache.clear
    world.query(Position, Size, Color, any: tags) do |entity_ids, positions, sizes, colors|
      i = 0
      len = entity_ids.length
      while i < len
        id = entity_ids[i]
        pos = positions[i]
        size = sizes[i]
        col = colors[i]

        cache[id] = {
          x: pos.x - size.w / 2,
          y: pos.y - size.h / 2,
          w: size.w,
          h: size.h,
          r: col.r,
          g: col.g,
          b: col.b
        }

        i += 1
      end
    end

    args.state.full_render = false
    return
  end

  world.query(Position, Size, Color, any: tags, changed: [Position]) do |entity_ids, positions, sizes, colors|
    i = 0
    len = entity_ids.length
    while i < len
      id = entity_ids[i]
      pos = positions[i]
      size = sizes[i]
      col = colors[i]

      prim = cache[id]
      unless prim
        prim = {
          x: 0,
          y: 0,
          w: size.w,
          h: size.h,
          r: col.r,
          g: col.g,
          b: col.b
        }
        cache[id] = prim
      end

      prim[:x] = pos.x - size.w / 2
      prim[:y] = pos.y - size.h / 2
      prim[:w] = size.w
      prim[:h] = size.h
      prim[:r] = col.r
      prim[:g] = col.g
      prim[:b] = col.b

      i += 1
    end
  end
end

def render(args, world)
  args.outputs.solids << { x: 0, y: 0, w: WORLD_W, h: WORLD_H, r: 15, g: 15, b: 20 }

  args.outputs.solids.concat(args.state.render_cache.values)

  args.outputs.labels << {
    x: 10,
    y: 710,
    text: "Avoider | Move: WASD/Arrows | Shoot: Click | Freeze Enemies: F | Reset: R | Score: #{args.state.score}",
    r: 240,
    g: 240,
    b: 240
  }

  args.outputs.labels << {
    x: 10,
    y: 690,
    text: "Entities: #{world.entity_count} | Updated this tick: #{world.count(Position, changed: [Position])}",
    r: 180,
    g: 180,
    b: 180
  }
end
