RESOLUTION = {
  w: 1280,
  h: 720
}

ANTS_COUNT = 1500
ANT_SIZE = 4
NEST_SIZE = 40

# Pheromone settings
PHEROMONE_DECAY = 0.995
PHEROMONE_STRENGTH = 100
PHEROMONE_SENSE_RADIUS = 30
PHEROMONE_GRID_SIZE = 10

# Ant behavior settings
ANT_SPEED = 2
ANT_TURN_SPEED = 0.3
ANT_WANDER_STRENGTH = 0.1
ANT_SENSE_ANGLE = 45

# Food settings
FOOD_SIZE = 8
FOOD_COUNT = 3
FOOD_PIECES_PER_SOURCE = 50_000

# Grid settings
GRID_COLS = (RESOLUTION.w / PHEROMONE_GRID_SIZE).ceil
GRID_ROWS = (RESOLUTION.h / PHEROMONE_GRID_SIZE).ceil

class Vector < Struct.new(:x, :y)
  def clear!
    self.x = 0.0
    self.y = 0.0
    self
  end

  def mul!(scalar)
    self.x *= scalar
    self.y *= scalar
    self
  end

  def add!(other)
    self.x += other.x
    self.y += other.y
    self
  end

  def magnitude
    Math.sqrt(x * x + y * y)
  end

  def normalize!
    m = magnitude
    return self if m.zero?
    self.x /= m
    self.y /= m
    self
  end

  def distance_to(other)
    dx = x - other.x
    dy = y - other.y
    Math.sqrt(dx * dx + dy * dy)
  end
end

# Component classes
Position = Class.new(Vector)
Velocity = Class.new(Vector)
Angle = Struct.new(:value)
AntState = Struct.new(:carrying_food, :target_food_id)
NestComponent = Struct.new(:food_stored)
FoodComponent = Struct.new(:amount)
PheromoneGrid = Struct.new(:to_food, :to_home)

def boot(args)
  args.state.entities = Drecs::World.new

  args.state.hook_ants_spawned = 0
  args.state.hook_food_removed = 0

  args.state.entities.on_added(AntState) { |_w, _id, _c| args.state.hook_ants_spawned += 1 }
  args.state.entities.on_removed(FoodComponent) { |_w, _id, _c| args.state.hook_food_removed += 1 }

  # Create pheromone grid
  to_food_grid = Array.new(GRID_COLS) { Array.new(GRID_ROWS) { 0.0 } }
  to_home_grid = Array.new(GRID_COLS) { Array.new(GRID_ROWS) { 0.0 } }
  args.state.pheromone_grid = PheromoneGrid.new(to_food_grid, to_home_grid)
  args.state.entities.spawn(args.state.pheromone_grid)

  # Create nest at center
  args.state.nest_id = args.state.entities.spawn(
    Position.new(RESOLUTION.w / 2, RESOLUTION.h / 2), 
    NestComponent.new(0)
  )

  # Create food sources
  FOOD_COUNT.times do
    angle = rand * Math::PI * 2
    distance = 200 + rand * 150
    fx = RESOLUTION.w / 2 + Math.cos(angle) * distance
    fy = RESOLUTION.h / 2 + Math.sin(angle) * distance
    args.state.entities.spawn(
      Position.new(fx, fy),
      FoodComponent.new(FOOD_PIECES_PER_SOURCE)
    )
  end

  # Create ants
  ANTS_COUNT.times do
    angle = rand * Math::PI * 2
    pos = Position.new(
      RESOLUTION.w / 2 + (rand - 0.5) * NEST_SIZE,
      RESOLUTION.h / 2 + (rand - 0.5) * NEST_SIZE
    )
    vel = Velocity.new(Math.cos(angle) * ANT_SPEED, Math.sin(angle) * ANT_SPEED)
    ant_angle = Angle.new(angle)
    ant_state = AntState.new(false, nil)

    args.state.entities.spawn(pos, vel, ant_angle, ant_state)
  end
end

def sense_pheromone(grid, x, y, angle_offset, current_angle)
  sense_angle = current_angle + angle_offset
  sense_x = x + Math.cos(sense_angle) * PHEROMONE_SENSE_RADIUS
  sense_y = y + Math.sin(sense_angle) * PHEROMONE_SENSE_RADIUS

  grid_x = (sense_x / PHEROMONE_GRID_SIZE).clamp(0, GRID_COLS - 1).to_i
  grid_y = (sense_y / PHEROMONE_GRID_SIZE).clamp(0, GRID_ROWS - 1).to_i

  grid[grid_x][grid_y]
end

def deposit_pheromone(grid, x, y, amount)
  grid_x = (x / PHEROMONE_GRID_SIZE).clamp(0, GRID_COLS - 1).to_i
  grid_y = (y / PHEROMONE_GRID_SIZE).clamp(0, GRID_ROWS - 1).to_i

  grid[grid_x][grid_y] += amount
end

def tick(args)
  # Get nest position
  nest_pos, nest_component = args.state.entities.get_many(args.state.nest_id, Position, NestComponent)

  # Get pheromone grids
  pheromone_grid = args.state.pheromone_grid
  to_food_grid = pheromone_grid.to_food
  to_home_grid = pheromone_grid.to_home

  # Decay pheromones
  GRID_COLS.times do |x|
    GRID_ROWS.times do |y|
      to_food_grid[x][y] *= PHEROMONE_DECAY
      to_home_grid[x][y] *= PHEROMONE_DECAY
    end
  end

  # Update ants
  args.state.entities.each_entity(Position, Velocity, Angle, AntState) do |entity_id, pos, vel, ant_angle, state|
    if state.carrying_food
      # Carrying food - follow "to home" pheromones and deposit "to food" pheromones
      deposit_pheromone(to_food_grid, pos.x, pos.y, PHEROMONE_STRENGTH)

      # Check if reached nest
      if pos.distance_to(nest_pos) < NEST_SIZE / 2
        state.carrying_food = false
        nest_component.food_stored += 1
      else
        # Follow to-home pheromones
        forward = sense_pheromone(to_home_grid, pos.x, pos.y, 0, ant_angle.value)
        left = sense_pheromone(to_home_grid, pos.x, pos.y, -ANT_SENSE_ANGLE * Math::PI / 180, ant_angle.value)
        right = sense_pheromone(to_home_grid, pos.x, pos.y, ANT_SENSE_ANGLE * Math::PI / 180, ant_angle.value)

        # Also add attraction to nest when close
        to_nest_x = nest_pos.x - pos.x
        to_nest_y = nest_pos.y - pos.y
        to_nest_angle = Math.atan2(to_nest_y, to_nest_x)
        angle_diff = to_nest_angle - ant_angle.value
        angle_diff = (angle_diff + Math::PI) % (2 * Math::PI) - Math::PI

        if left > forward && left > right
          ant_angle.value -= ANT_TURN_SPEED
        elsif right > forward && right > left
          ant_angle.value += ANT_TURN_SPEED
        else
          ant_angle.value += (rand - 0.5) * ANT_WANDER_STRENGTH
        end

        # Bias toward nest when carrying food
        ant_angle.value += angle_diff * 0.1
      end
    else
      # Searching for food - follow "to food" pheromones and deposit "to home" pheromones
      deposit_pheromone(to_home_grid, pos.x, pos.y, PHEROMONE_STRENGTH)

      food_found = false
      closest_food_dist = Float::INFINITY
      closest_food_angle = nil

      args.state.entities.each_entity(Position, FoodComponent) do |entity_id, food_pos, food_comp|
        next if food_comp.amount <= 0

        dist = pos.distance_to(food_pos)

        # Check if can pickup food
        if dist < FOOD_SIZE
          state.carrying_food = true
          food_comp.amount -= 1
          food_found = true

          # Destroy food source if empty
          if food_comp.amount <= 0
            args.state.entities.destroy(entity_id)
          end
          break
        elsif dist < 50 && dist < closest_food_dist
          # Track closest food for attraction
          closest_food_dist = dist
          to_food_x = food_pos.x - pos.x
          to_food_y = food_pos.y - pos.y
          closest_food_angle = Math.atan2(to_food_y, to_food_x)
        end
      end

      unless food_found
        # Follow to-food pheromones
        forward = sense_pheromone(to_food_grid, pos.x, pos.y, 0, ant_angle.value)
        left = sense_pheromone(to_food_grid, pos.x, pos.y, -ANT_SENSE_ANGLE * Math::PI / 180, ant_angle.value)
        right = sense_pheromone(to_food_grid, pos.x, pos.y, ANT_SENSE_ANGLE * Math::PI / 180, ant_angle.value)

        if left > forward && left > right
          ant_angle.value -= ANT_TURN_SPEED
        elsif right > forward && right > left
          ant_angle.value += ANT_TURN_SPEED
        else
          ant_angle.value += (rand - 0.5) * ANT_WANDER_STRENGTH
        end

        # If food detected nearby, bias toward it strongly
        if closest_food_angle
          angle_diff = closest_food_angle - ant_angle.value
          angle_diff = (angle_diff + Math::PI) % (2 * Math::PI) - Math::PI
          ant_angle.value += angle_diff * 0.2
        end
      end
    end

    # Update velocity based on angle
    vel.x = Math.cos(ant_angle.value) * ANT_SPEED
    vel.y = Math.sin(ant_angle.value) * ANT_SPEED

    # Update position
    pos.x += vel.x
    pos.y += vel.y

    # Wrap around screen
    pos.x = (pos.x + RESOLUTION[:w]) % RESOLUTION[:w]
    pos.y = (pos.y + RESOLUTION[:h]) % RESOLUTION[:h]
  end

  # Render
  args.outputs.solids << { x: 0, y: 0, w: RESOLUTION.w, h: RESOLUTION.h, r: 0, g: 0, g: 0 }

  # Render pheromones (optional - can be toggled with key)
  if args.state.show_pheromones
    GRID_COLS.times do |x|
      GRID_ROWS.times do |y|
        food_strength = (to_food_grid[x][y] / 50.0).clamp(0, 1) * 255
        home_strength = (to_home_grid[x][y] / 50.0).clamp(0, 1) * 255

        if food_strength > 5 || home_strength > 5
          args.outputs.solids << {
            x: x * PHEROMONE_GRID_SIZE,
            y: y * PHEROMONE_GRID_SIZE,
            w: PHEROMONE_GRID_SIZE,
            h: PHEROMONE_GRID_SIZE,
            r: home_strength,
            g: 0,
            b: food_strength,
            a: ([food_strength, home_strength].max * 0.5).to_i
          }
        end
      end
    end
  end

  # Render nest
  args.outputs.solids << {
    x: nest_pos.x - NEST_SIZE / 2,
    y: nest_pos.y - NEST_SIZE / 2,
    w: NEST_SIZE,
    h: NEST_SIZE,
    r: 139,
    g: 69,
    b: 19
  }

  # Render food sources
  args.state.entities.query(Position, FoodComponent) do |entity_ids, positions, food_comps|
    Array.each_with_index(positions) do |food_pos, i|
      args.outputs.solids << {
        x: food_pos.x - FOOD_SIZE,
        y: food_pos.y - FOOD_SIZE,
        w: FOOD_SIZE * 2,
        h: FOOD_SIZE * 2,
        r: 0,
        g: 255,
        b: 0
      }
    end
  end

  # Render ants
  args.state.entities.query(Position, AntState) do |entity_ids, positions, states|
    Array.each_with_index(positions) do |pos, i|
      state = states[i]

      args.outputs.solids << {
        x: pos.x - ANT_SIZE / 2,
        y: pos.y - ANT_SIZE / 2,
        w: ANT_SIZE,
        h: ANT_SIZE,
        r: state.carrying_food ? 255 : 255,
        g: state.carrying_food ? 215 : 255,
        b: state.carrying_food ? 0 : 255
      }
    end
  end

  # Toggle pheromone visualization
  if args.inputs.keyboard.key_down.p
    args.state.show_pheromones = !args.state.show_pheromones
  end

  # Debug info
  args.outputs.labels << { x: 10, y: RESOLUTION.h - 10, text: "FPS: #{args.gtk.current_framerate.to_i}", r: 255, g: 255, b: 255 }
  args.outputs.labels << { x: 10, y: RESOLUTION.h - 30, text: "Food stored: #{nest_component.food_stored}", r: 255, g: 255, b: 255 }
  args.outputs.labels << { x: 10, y: RESOLUTION.h - 50, text: "Hooks: Ants +#{args.state.hook_ants_spawned} | Food removed #{args.state.hook_food_removed}", r: 220, g: 220, b: 220 }
  args.outputs.labels << { x: 10, y: RESOLUTION.h - 70, text: "Press P to toggle pheromones", r: 255, g: 255, b: 255 }
end
