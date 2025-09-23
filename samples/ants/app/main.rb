Position = Struct.new(:x, :y)
Velocity = Struct.new(:x, :y)
Ant = Struct.new(:food_pheromone, :home_pheromone, :distance_traveled)
Pheromone = Struct.new(:type, :strength)
Nest = Struct.new("Nest")
Foraging = Struct.new("Foraging")
ReturningHome = Struct.new("ReturningHome")
FollowingFoodTrail = Struct.new("FollowingFoodTrail")
FoodSource = Struct.new(:quantity)
CarryingFood = Struct.new("CarryingFood")
Drawable = Struct.new(:r, :g, :b, :a, :w, :h)

NUM_ANTS = 1
NUM_FOOD_SOURCES = 4 

def boot(args)
    args.state.entities = Drecs::World.new

    args.state.config = {
      max_speed: 1.5,
      jitter: 0.2,
      pheromone_attract_radius: 120.0,
      pheromone_influence: 0.05,
      nest_influence: 0.08,
      pickup_radius: 12.0,
      nest_drop_radius: 15.0,
      food_detect_radius: 200.0,
      food_target_influence: 0.15,
      pheromone_use_rate: 0.995,
      distance_traveled_threshold: 25
    }

    args.state.entities.spawn(
        Nest.new,
        Position.new(400, 300),
        Drawable.new(255, 255, 100, 255, 10, 10)
    )
    NUM_ANTS.times do 
        args.state.entities.spawn(
            Ant.new(100, 100, 0),
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
  args.state.entities.query(Ant, Position, Velocity, Foraging) do |ants, positions, velocities, _foraging, entity_ids|
    food = args.state.entities.query(FoodSource, Position)
    ants.each_with_index do |ant, index|
      pos = positions[index]
      vel = velocities[index]

      vel.x += Numeric.rand(-args.state.config[:jitter]..args.state.config[:jitter])
      vel.y += Numeric.rand(-args.state.config[:jitter]..args.state.config[:jitter])

      food.each_with_index do |(food_source, food_positions), food_index|
        food_pos = food_positions[food_index]
        if Geometry.distance(pos, food_pos) < args.state.config[:food_detect_radius]
          vel.x = (food_pos.x - pos.x) * args.state.config[:food_target_influence]
          vel.y = (food_pos.y - pos.y) * args.state.config[:food_target_influence]
          p vel
        end

        if Geometry.distance(pos, food_pos) < args.state.config[:pickup_radius]
          args.state.entities.add_component(entity_ids[index], CarryingFood)
          args.state.entities.remove_component(entity_ids[index], Foraging)
        end
      end
    end
  end

  args.state.entities.query(Ant, Position, Velocity, CarryingFood) do |ants, positions, velocities, _carrying_food, entity_ids|
    ants.each_with_index do |ant, index|
      pos = positions[index]
      vel = velocities[index]

      vel.x += Numeric.rand(-args.state.config[:jitter]..args.state.config[:jitter])
      vel.y += Numeric.rand(-args.state.config[:jitter]..args.state.config[:jitter])

      nest = args.state.entities.query(Nest, Position)

      nest_pos = nest[1][0]
      if Geometry.distance(pos, nest_pos) < args.state.config[:nest_drop_radius]
        args.state.entities.remove_component(entity_ids[index], CarryingFood)
        args.state.entities.add_component(entity_ids[index], ReturningHome)
      end
    end
  end

  # cap to max speed
  args.state.entities.query(Velocity) do |velocities|
    velocities.each do |vel|
      speed = Math.sqrt(vel.x * vel.x + vel.y * vel.y)
      if speed > args.state.config[:max_speed]
        scale = args.state.config[:max_speed] / speed
        vel.x *= scale
        vel.y *= scale
      end
    end
  end

  # Foraging ants lay home pheromones to help guide the return path
  args.state.entities.query(Ant, Position, Foraging) do |ants, positions|
    ants.each_with_index do |ant, i|
      if ant.distance_traveled > args.state.config.distance_traveled_threshold
        args.state.entities.spawn(
          Pheromone.new(:home, ant.home_pheromone * args.state.config.pheromone_use_rate),
          Position.new(positions[i].x, positions[i].y),
          Drawable.new(0, 255, 50, 255, 2, 2)
        )
        ant.distance_traveled = 0
      end
    end
  end

  # Returning ants carrying food lay food pheromones to guide others to the source
  args.state.entities.query(Ant, Position, CarryingFood) do |ants, positions|
    ants.each_with_index do |ant, i|
      if ant.distance_traveled > args.state.config.distance_traveled_threshold
        args.state.entities.spawn(
          Pheromone.new(:food, ant.food_pheromone * args.state.config.pheromone_use_rate),
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

  args.state.entities.query(Ant, Position, Velocity) do |ants, positions, velocities|
    ants.each_with_index do |ant, index|
      before = positions[index].dup
      positions[index].x += velocities[index].x
      positions[index].y += velocities[index].y
      ant.distance_traveled += Geometry.distance(before, positions[index])
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
