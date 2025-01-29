include Drecs::Main

RESOLUTION = {
  w: 1280,
  h: 720
}


BOIDS_COUNT = 1000

SEPARATION_WEIGHT = 20
ALIGNMENT_WEIGHT = 1.0
COHESION_WEIGHT = 1.0

MOVEMENT_ACCURACY = 1

NEIGHBOUR_RANGE = 10
MIN_VELOCITY = 2
MAX_VELOCITY = 10

GRID_CELL_SIZE = NEIGHBOUR_RANGE
GRID_COLS = (RESOLUTION.w / GRID_CELL_SIZE).ceil
GRID_ROWS = (RESOLUTION.h / GRID_CELL_SIZE).ceil

component :position, x: 0, y: 0
component :size, w: 0, h: 0
component :color, r: 0, g: 0, b: 0, a: 255
component :acceleration, value: 0
component :behavior, center: { x: 0, y: 0 }, direction: { x: 0, y: 0 }, count: 0
component :velocity, x: 0, y: 0

def neighbours(entity, entities) 
  grid_x = (entity.position.x / GRID_CELL_SIZE).floor
  grid_y = (entity.position.y / GRID_CELL_SIZE).floor
  
  # Check current cell and adjacent cells
  nearby_entities = []
  (-1..1).each do |dx|
    (-1..1).each do |dy|
      check_x = grid_x + dx
      check_y = grid_y + dy
      
      next if check_x < 0 || check_x >= GRID_COLS || check_y < 0 || check_y >= GRID_ROWS
      
      nearby_entities.concat($args.state.grid[check_x][check_y])
    end
  end
  
  nearby_entities
end

COHESION = { x: 0, y: 0 }
SEPARATION = { x: 0, y: 0 }
ALIGNMENT = { x: 0, y: 0 }
DIFF = { x: 0, y: 0 }
MOUSE = { x: 0, y: 0 }

system :movement, :position, :velocity do |entities|
  Array.each(entities) do |entity|
    pos = entity.position
    vel = entity.velocity
    
    # Reset vectors
    COHESION.x = 0
    COHESION.y = 0
    SEPARATION.x = 0
    SEPARATION.y = 0
    ALIGNMENT.x = 0
    ALIGNMENT.y = 0

    neighbours = neighbours(entity, entities)
    
    unless neighbours.empty?
      n_length = neighbours.length.to_f
      
      Array.each(neighbours) do |other|
        other_pos = other.position
        other_vel = other.velocity
        
        # Calculate separation
        DIFF.x = pos.x - other_pos.x
        DIFF.y = pos.y - other_pos.y
        
        dist = Geometry.vec2_magnitude(DIFF)
        if dist < NEIGHBOUR_RANGE && dist > 0
          scale = 1.0 / dist
          vec2_div(DIFF, dist)
          vec2_mul(DIFF, scale)
          vec2_add(SEPARATION, DIFF)
        end
        
        # Accumulate cohesion and alignment
        vec2_add(COHESION, other_pos)
        vec2_add(ALIGNMENT, other_vel)
      end
      
      if inputs.mouse.left
        MOUSE.x = inputs.mouse.x
        MOUSE.y = inputs.mouse.y
        COHESION.x = MOUSE.x
        COHESION.y = MOUSE.y
      else
        vec2_div(COHESION, n_length)
      end
      vec2_sub(COHESION, pos)
      vec2_div(COHESION, 100)
      vec2_mul(COHESION, COHESION_WEIGHT)
      
      vec2_mul(SEPARATION, SEPARATION_WEIGHT)
      
      vec2_div(ALIGNMENT, n_length)
      vec2_sub(ALIGNMENT, vel)
      vec2_div(ALIGNMENT, 4)
      vec2_mul(ALIGNMENT, ALIGNMENT_WEIGHT)
      
      # Combine forces and update velocity
      vec2_add(COHESION, SEPARATION)
      vec2_add(COHESION, ALIGNMENT)
      vec2_add(vel, COHESION)
      
      # Constrain velocity in place
      magnitude = Geometry.vec2_magnitude(vel)
      if magnitude < MIN_VELOCITY
        scale = MIN_VELOCITY / magnitude
        vec2_mul(vel, scale)
      elsif magnitude > MAX_VELOCITY
        scale = MAX_VELOCITY / magnitude
        vec2_mul(vel, scale)
      end
      
      # Update position
      vec2_add(pos, vel)
      
      pos.x = (pos.x + RESOLUTION[:w]) % RESOLUTION[:w]
      pos.y = (pos.y + RESOLUTION[:h]) % RESOLUTION[:h]

      p "We broke it #{pos.x}, #{pos.y}, #{vel}" if pos.x.nan?
    end
  end
end

system :update_grid do |entities|
  # Clear the grid
  GRID_COLS.times do |x|
    GRID_ROWS.times do |y|
      state.grid[x][y].clear
    end
  end

  # Place each entity in its grid cell
  Array.each(entities) do |entity|
    grid_x = (entity.position.x / GRID_CELL_SIZE).floor
    grid_y = (entity.position.y / GRID_CELL_SIZE).floor
    
    # Ensure within bounds
    grid_x = [[grid_x, 0].max, GRID_COLS - 1].min
    grid_y = [[grid_y, 0].max, GRID_ROWS - 1].min
    
    state.grid[grid_x][grid_y] << entity 
  end
end

system :draw, :position, :size, :color do |entities|
  outputs.solids << Array.map(entities) do |entity| 
    {
      x: entity.position.x,
      y: entity.position.y,
      w: entity.size.w,
      h: entity.size.h,
      r: entity.color.r,
      g: entity.color.g,
      b: entity.color.b,
      a: entity.color.a
    } 
  end
end

def vec2_div(a, b)
  a.x /= b 
  a.y /= b
end

def vec2_mul(a, b)
  a.x *= b
  a.y *= b
end

def vec2_sub(a, b)
  a.x -= b.x
  a.y -= b.y
end

def vec2_add(a, b)
  a.x += b.x
  a.y += b.y
end


def create_boid
  boid = create_entity(:boid)
  add_component(boid, :position, x: rand * RESOLUTION.w, y: rand * RESOLUTION.h)
  add_component(boid, :size, w: Numeric.rand(5..5), h: Numeric.rand(5..5))
  add_component(boid, :color, r: rand(255), g: rand(255), b: rand(255), a: 255)

  velocity = Geometry.vec2_normalize({ x: rand - 0.5, y: rand - 0.5 })
  operand = (MIN_VELOCITY + (rand * (MAX_VELOCITY - MIN_VELOCITY)))
  velocity = {
    x: velocity.x * operand,
    y: velocity.y * operand
  }
  add_component(boid, :velocity, velocity)

  boid
end

world :default, systems: [:update_grid, :movement, :draw]

def boot(args)
  args.state.grid = Array.new(GRID_COLS) { Array.new(GRID_ROWS) { [] } }

  set_world :default
  BOIDS_COUNT.times do 
    create_boid
  end
end

def tick(args)
  process_systems(args, debug: true)

  args.outputs.debug << "#{args.gtk.current_framerate} fps"
  args.outputs.debug << "#{args.gtk.current_framerate_calc} fps simulation"
  args.outputs.debug << "#{args.gtk.current_framerate_render} fps render"
  args.outputs.debug << "boids: #{BOIDS_COUNT}"
end