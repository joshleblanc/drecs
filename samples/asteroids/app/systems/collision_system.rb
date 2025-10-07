class CollisionSystem
  def call(world, args)
    bullets = []
    world.each_entity(Bullet, Position, Collider) do |entity_id, bullet, pos, collider|
      bullets << { id: entity_id, pos: pos, radius: collider.radius }
    end

    asteroids = []
    world.each_entity(Asteroid, Position, Collider) do |entity_id, asteroid, pos, collider|
      asteroids << { id: entity_id, asteroid: asteroid, pos: pos, radius: collider.radius }
    end

    player = nil
    world.each_entity(Player, Position, Collider) do |entity_id, p, pos, collider|
      player = { id: entity_id, pos: pos, radius: collider.radius }
    end

    entities_to_destroy = []
    asteroids_to_split = []

    bullets.each do |bullet|
      asteroids.each do |asteroid|
        if colliding?(bullet[:pos], bullet[:radius], asteroid[:pos], asteroid[:radius])
          entities_to_destroy << bullet[:id]
          entities_to_destroy << asteroid[:id]
          asteroids_to_split << asteroid
          args.state.score ||= 0
          args.state.score += asteroid[:asteroid].size * 10
        end
      end
    end

    if player
      asteroids.each do |asteroid|
        if colliding?(player[:pos], player[:radius], asteroid[:pos], asteroid[:radius])
          args.state.game_over = true
        end
      end
    end

    world.destroy(*entities_to_destroy.uniq) unless entities_to_destroy.empty?

    asteroids_to_split.each do |asteroid|
      next if asteroid[:asteroid].size <= 1
      split_asteroid(world, asteroid)
    end
  end

  private

  def colliding?(pos1, r1, pos2, r2)
    dx = pos1.x - pos2.x
    dy = pos1.y - pos2.y
    distance = Math.sqrt(dx * dx + dy * dy)
    distance < (r1 + r2)
  end

  def split_asteroid(world, asteroid_data)
    size = asteroid_data[:asteroid].size
    return if size <= 1

    new_size = size - 1
    pos = asteroid_data[:pos]

    2.times do
      angle = rand(360) * Math::PI / 180
      speed = 1 + rand(2)

      world.spawn(
        Position.new(pos.x, pos.y),
        Velocity.new(Math.cos(angle) * speed, Math.sin(angle) * speed),
        Rotation.new(rand(360), Numeric.rand(-2.0..2.0)),
        Asteroid.new(new_size),
        Collider.new(10 * new_size),
        Polygon.new(
          generate_asteroid_points(new_size),
          200, 200, 200
        )
      )
    end
  end

  def generate_asteroid_points(size)
    radius = 10 * size
    num_points = 8
    points = []

    num_points.times do |i|
      angle = (i / num_points.to_f) * 2 * Math::PI
      r = radius + Numeric.rand(-radius * 0.3..radius * 0.3)
      points << [Math.cos(angle) * r, Math.sin(angle) * r]
    end

    points
  end
end
