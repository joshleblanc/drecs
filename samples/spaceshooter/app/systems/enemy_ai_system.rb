class EnemyAISystem
  def call(world, args)
    world.each_entity(Enemy, Position, Velocity) do |entity_id, enemy, pos, vel|
      if pos.x <= 50 || pos.x >= 1230
        enemy.direction *= -1
        vel.x = enemy.direction * 2
      end

      if rand < 0.02
        vel.y = -1 + rand * 2
      end
    end
  end
end
