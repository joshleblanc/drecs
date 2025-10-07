class BulletSystem
  def call(world, args)
    to_destroy = []

    world.each_entity(Bullet) do |entity_id, bullet|
      bullet.lifetime -= 1
      to_destroy << entity_id if bullet.lifetime <= 0
    end

    world.destroy(*to_destroy) unless to_destroy.empty?
  end
end
