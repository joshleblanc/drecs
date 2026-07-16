# CollisionSystem - handles collision detection between projectiles and targets
# This system showcases: AABB collision, archetype-based optimization,
#                       and deferred world mutations via commands
class CollisionSystem
  def call(world, args)
    projectiles = []
    world.each_chunk(Position, Collider, Projectile) do |entity_ids, positions, colliders, _projectiles|
      i = 0
      len = entity_ids.length
      while i < len
        projectiles << [entity_ids[i], positions[i], colliders[i]]
        i += 1
      end
    end

    targets = []
    world.each_chunk(Position, Collider, any: [Player, Enemy]) do |entity_ids, positions, colliders|
      i = 0
      len = entity_ids.length
      while i < len
        targets << [entity_ids[i], positions[i], colliders[i]]
        i += 1
      end
    end

    # Collect hits for deferred processing
    hits = []

    pi = 0
    while pi < projectiles.length
      proj_id, proj_pos, proj_coll = projectiles[pi]

      ti = 0
      while ti < targets.length
        target_id, target_pos, target_coll = targets[ti]

        # Skip if targeting own projectiles (handled by Projectile.owner_id check in event system)
        next if proj_id == target_id

        dx = proj_pos.x - target_pos.x
        dy = proj_pos.y - target_pos.y
        dist = Math.sqrt(dx * dx + dy * dy)

        if dist < proj_coll.radius + target_coll.radius
          hits << [proj_id, target_id]
        end

        ti += 1
      end
      pi += 1
    end

    # Use commands for deferred destruction during iteration
    hits.each do |proj_id, target_id|
      proj = world.get_component(proj_id, Projectile)
      if proj && proj.owner_id != target_id
        world.send_event(HitEvent.new(proj_id, target_id, proj.damage))
        world.commands { |cmd| cmd.destroy(proj_id) }
      end
    end
  end
end