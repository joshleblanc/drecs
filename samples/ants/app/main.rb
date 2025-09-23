Position = Struct.new(:x, :y)
Velocity = Struct.new(:x, :y)
Ant = Struct.new(:energy, :distance_traveled)
Pheromone = Struct.new(:type, :strength)
Nest = Struct.new("Nest")
Foraging = Struct.new("Foraging")
ReturningHome = Struct.new("ReturningHome")
FollowingFoodTrail = Struct.new("FollowingFoodTrail")
FoodSource = Struct.new(:quantity)
CarryingFood = Struct.new("CarryingFood")
Drawable = Struct.new(:r, :g, :b, :a, :w, :h)

NUM_ANTS = 1
NUM_FOOD_SOURCES = 1 

def boot(args)
    args.state.entities = Drecs::World.new
    args.state.entities.spawn(
        Nest.new,
        Position.new(400, 300),
        Drawable.new(255, 255, 100, 255, 10, 10)
    )
    NUM_ANTS.times do 
        args.state.entities.spawn(
            Ant.new(100, 0),
            Position.new(400, 300),
            Velocity.new(Numeric.rand(-1.0..1.0), Numeric.rand(-1.0..1.0)),
            Foraging.new,
            Drawable.new(0, 0, 0, 255, 5, 5)
        )
    end

    NUM_FOOD_SOURCES.times do
        pos = Position.new(Numeric.rand(0..800), Numeric.rand(0..600))
        args.state.entities.spawn(
            FoodSource.new(50),
            pos,
            Drawable.new(255, 0, 0, 255, 10, 10)
        )


    end 
end

def tick(args)
 
  # Movement constants
  max_speed = 1.5
  jitter = 0.2
  pheromone_attract_radius = 120.0
  pheromone_influence = 0.05
  nest_influence = 0.08
  pickup_radius = 12.0
  nest_drop_radius = 15.0
  food_detect_radius = 200.0
  food_target_influence = 0.15

  # Cache nest position(s) for this tick
  nest_positions = []
  args.state.entities.query(Nest, Position) do |nests, positions|
    nest_positions = positions.dup
  end

  # Cache home pheromones (position + strength) for this tick
  home_pheromones = []
  args.state.entities.query(Pheromone, Position) do |pheromones, positions|
    pheromones.each_with_index do |ph, i|
      if ph.type == :home
        home_pheromones << { pos: positions[i], strength: ph.strength }
      end
    end
  end

  # Cache food pheromones (position + strength) for this tick
  food_pheromones = []
  args.state.entities.query(Pheromone, Position) do |pheromones, positions|
    pheromones.each_with_index do |ph, i|
      if ph.type == :food
        food_pheromones << { pos: positions[i], strength: ph.strength }
      end
    end
  end
  
  # Cache food sources (position + food component + entity id)
  food_sources = []
  args.state.entities.query(FoodSource, Position) do |foods, positions, entity_ids|
    foods.each_with_index do |f, i|
      food_sources << { pos: positions[i], food: f, id: entity_ids[i] }
    end
  end
 
  pickup_actions = []
  args.state.entities.query(Ant, Position, Velocity, Foraging) do |ants, positions, velocities, _foraging, entity_ids|
    ants.each_with_index do |ant, index|
      # Wander randomly with slight attraction to nearby food pheromones
      pos = positions[index]
      vel = velocities[index]

      vx = vel.x
      vy = vel.y

      # Random jitter for wandering
      vx += Numeric.rand(-jitter..jitter)
      vy += Numeric.rand(-jitter..jitter)

      # Direct attraction toward visible food sources (prioritized)
      nearest_dx = 0.0
      nearest_dy = 0.0
      nearest_d2 = food_detect_radius * food_detect_radius
      food_sources.each do |fs|
        next if fs[:food].quantity <= 0
        dx = fs[:pos].x - pos.x
        dy = fs[:pos].y - pos.y
        d2 = dx * dx + dy * dy
        if d2 < nearest_d2
          nearest_d2 = d2
          nearest_dx = dx
          nearest_dy = dy
        end
      end

      pheromone_scale = 1.0
      if nearest_d2 < food_detect_radius * food_detect_radius
        distf = Math.sqrt(nearest_d2)
        if distf > 0
          vx += food_target_influence * (nearest_dx / distf)
          vy += food_target_influence * (nearest_dy / distf)
        end
        # When food is in sight, downweight pheromone influence
        pheromone_scale = 0.25
      end

      # Attraction toward food pheromones: weighted by strength and proximity
      sum_x = 0.0
      sum_y = 0.0
      radius2 = pheromone_attract_radius * pheromone_attract_radius
      food_pheromones.each do |fp|
        dx = fp[:pos].x - pos.x
        dy = fp[:pos].y - pos.y
        d2 = dx * dx + dy * dy
        next unless d2 < radius2
        dist = Math.sqrt(d2)
        next if dist <= 1.0
      vx += pheromone_influence * pheromone_scale * sum_x
      vy += pheromone_influence * pheromone_scale * sum_y

      # Clamp to max speed
      speed = Math.sqrt(vx * vx + vy * vy)
      if speed > max_speed
        scale = max_speed / speed
        vx *= scale
        vy *= scale
      end

      vel.x = vx
      vel.y = vy
      ant.distance_traveled += speed

      # If close enough to a food source, pick up food
      best_fs = nil
      best_d2 = pickup_radius * pickup_radius
      food_sources.each do |fs|
        next if fs[:food].quantity <= 0
        dx = fs[:pos].x - pos.x
        dy = fs[:pos].y - pos.y
        d2 = dx * dx + dy * dy
        if d2 < best_d2
          best_d2 = d2
          best_fs = fs
        end
      end
      if best_fs
        pickup_actions << { ant_id: entity_ids[index], fs: best_fs }
      end
    end
  end

  drop_actions = []
  args.state.entities.query(Ant, Position, Velocity, ReturningHome, CarryingFood) do |ants, positions, velocities, _returning, _carrying, entity_ids|
    ants.each_with_index do |ant, index|
      # Wander with jitter and steer toward the nest if present
      pos = positions[index]
      vel = velocities[index]

      vx = vel.x
      vy = vel.y

      # Small jitter so they don't look too uniform
      vx += Numeric.rand(-(jitter / 2.0)..(jitter / 2.0))
      vy += Numeric.rand(-(jitter / 2.0)..(jitter / 2.0))

      # Attraction toward home pheromones: weighted by strength and proximity
      sum_x = 0.0
      sum_y = 0.0
      radius2 = pheromone_attract_radius * pheromone_attract_radius
        next if dist <= 1.0
        # Weight increases with strength and decreases with distance
        w = hp[:strength].to_f / (dist + 1.0)
        sum_x += (dx / dist) * w
        sum_y += (dy / dist) * w
      end
      # Apply the weighted attraction
      vx += pheromone_influence * sum_x
      vy += pheromone_influence * sum_y

      if nest_positions.any?
        nest_pos = nest_positions.first
        dx = nest_pos.x - pos.x
        dy = nest_pos.y - pos.y
        dist = Math.sqrt(dx * dx + dy * dy)
        if dist > 0
          vx += nest_influence * (dx / dist)
          vy += nest_influence * (dy / dist)
        end
      end

      # Clamp to max speed
      speed = Math.sqrt(vx * vx + vy * vy)
      if speed > max_speed
        scale = max_speed / speed
        vx *= scale
        vy *= scale
      end

      vel.x = vx
      vel.y = vy
      ant.distance_traveled += speed

      # If close enough to the nest, drop food and resume foraging
      if nest_positions.any?
        nest_pos = nest_positions.first
        dxn = nest_pos.x - pos.x
        dyn = nest_pos.y - pos.y
        if (dxn * dxn + dyn * dyn) <= (nest_drop_radius * nest_drop_radius)
          drop_actions << entity_ids[index]
        end
      end
    end
  end

  args.state.entities.query(Ant, Position, Velocity, FollowingFoodTrail) do |ants, positions, velocities, _following, entity_ids|
    ants.each_with_index do |ant, index|
      pos = positions[index]
      vel = velocities[index]

      vx = vel.x
      vy = vel.y

      # Random jitter for wandering
      vx += Numeric.rand(-jitter..jitter)
      vy += Numeric.rand(-jitter..jitter)

      # Attraction toward food pheromones: weighted by strength and proximity
      sum_x = 0.0
      sum_y = 0.0
      radius2 = pheromone_attract_radius * pheromone_attract_radius
      food_pheromones.each do |fp|
        dx = fp[:pos].x - pos.x
        dy = fp[:pos].y - pos.y
        d2 = dx * dx + dy * dy
        next unless d2 < radius2
        dist = Math.sqrt(d2)
        next if dist <= 1.0
        # Weight increases with strength and decreases with distance
        w = fp[:strength].to_f / (dist + 1.0)
        sum_x += (dx / dist) * w
        sum_y += (dy / dist) * w
      end

      if sum_x.zero? && sum_y.zero?
        # No food pheromones found, switch back to foraging
        args.state.entities.remove_component(entity_ids[index], FollowingFoodTrail)
        args.state.entities.add_component(entity_ids[index], Foraging.new)
      else
        # Apply the weighted attraction
        vx += pheromone_influence * sum_x
        vy += pheromone_influence * sum_y
      end

      # Clamp to max speed
      speed = Math.sqrt(vx * vx + vy * vy)
      if speed > max_speed
        scale = max_speed / speed
        vx *= scale
        vy *= scale
      end

      vel.x = vx
      vel.y = vy
      ant.distance_traveled += speed
    end
  end

  # Apply food pickup actions outside the query loop to avoid mutating while iterating
  unless pickup_actions.empty?
    world = args.state.entities
    to_destroy_food_ids = []
    pickup_actions.each do |act|
      fs = act[:fs]
      ant_id = act[:ant_id]
      # Decrement food source
      fs[:food].quantity -= 1
      to_destroy_food_ids << fs[:id] if fs[:food].quantity <= 0

      # Switch ant state to ReturningHome and mark as CarryingFood
      world.add_component(ant_id, CarryingFood.new)
      world.add_component(ant_id, ReturningHome.new)
      world.remove_component(ant_id, Foraging) if world.has_component?(ant_id, Foraging)
      world.remove_component(ant_id, FollowingFoodTrail) if world.has_component?(ant_id, FollowingFoodTrail)
    end
    world.destroy(*to_destroy_food_ids) unless to_destroy_food_ids.empty?
  end

  # Apply drop actions outside the query loop
  unless drop_actions.empty?
    world = args.state.entities
    drop_actions.each do |ant_id|
      world.remove_component(ant_id, ReturningHome)
      world.remove_component(ant_id, CarryingFood)
      world.add_component(ant_id, FollowingFoodTrail.new)
    end
  end

  # Food sources continuously emit food pheromones
  args.state.entities.query(FoodSource, Position) do |foods, positions|
    next unless args.state.tick_count % 30 == 0
    foods.each_with_index do |food, i|
      next if food.quantity <= 0
      strength = food.quantity * 0.1
      strength = 1.0 if strength < 1.0
      strength = 10.0 if strength > 10.0
      args.state.entities.spawn(
        Pheromone.new(:food, strength),
        Position.new(positions[i].x, positions[i].y),
        Drawable.new(0, 255, 255, 255, 10, 10)
      )
    end
  end

  # Foraging ants lay home pheromones to help guide the return path
  args.state.entities.query(Ant, Position, Foraging) do |ants, positions, _foraging, entity_ids|
    ants.each_with_index do |ant, i|
      if ant.distance_traveled > 25
        args.state.entities.spawn(
          Pheromone.new(:home, 50),
          Position.new(positions[i].x, positions[i].y),
          Drawable.new(0, 255, 50, 255, 2, 2)
        )
        ant.distance_traveled = 0
      end
    end
  end

  # Returning ants carrying food lay food pheromones to guide others to the source
  args.state.entities.query(Ant, Position, ReturningHome, CarryingFood) do |ants, positions, _returning, _carrying, entity_ids|
    ants.each_with_index do |ant, i|
      if ant.distance_traveled > 25
        args.state.entities.spawn(
          Pheromone.new(:food, 50),
          Position.new(positions[i].x, positions[i].y),
          Drawable.new(50, 255, 255, 255, 2, 2)
        )
        ant.distance_traveled = 0
      end
    end
  end

  args.state.entities.query(Pheromone) do |pheromones, entity_ids|
    to_destroy = []
    pheromones.each_with_index do |pheromone, index|
      pheromone.strength -= 0.1
      to_destroy << entity_ids[index] if pheromone.strength <= 0
    end
    args.state.entities.destroy(*to_destroy) unless to_destroy.empty?
  end

  args.state.entities.query(Position, Velocity) do |positions, velocities|
    positions.each_with_index do |position, index|
      position.x += velocities[index].x
      position.y += velocities[index].y
    end
  end

  args.state.entities.query(Position, Drawable) do |positions, drawables|
    solids = []
    positions.each_with_index do |position, index|
      solids << { x: position.x, y: position.y, w: drawables[index].w, h: drawables[index].h, r: drawables[index].r, g: drawables[index].g, b: drawables[index].b, a: drawables[index].a }
    end
    args.outputs.solids << solids
  end
end
