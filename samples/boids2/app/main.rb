RESOLUTION = {
  w: 1280,
  h: 720
}

BOIDS_COUNT = 3000

SEPARATION_WEIGHT = 20
ALIGNMENT_WEIGHT = 1.0
COHESION_WEIGHT = 1.0

BOUNCE = false

MOVEMENT_ACCURACY = 2

NEIGHBOUR_RANGE = 10
MIN_VELOCITY = 2
MAX_VELOCITY = 10

GRID_CELL_SIZE = NEIGHBOUR_RANGE
GRID_COLS = (RESOLUTION.w / GRID_CELL_SIZE).ceil
GRID_ROWS = (RESOLUTION.h / GRID_CELL_SIZE).ceil

COHESION = { x: 0, y: 0 }
SEPARATION = { x: 0, y: 0 }
ALIGNMENT = { x: 0, y: 0 }
DIFF = { x: 0, y: 0 }
MOUSE = { x: 0, y: 0 }

ALIGNMENT_DIVISOR = 4
COHESION_DIVISOR = 100


GRID_RANGE = -1..1

def neighbours(entity, entities, grid, &blk) 
  grid_x = (entity.position.x / GRID_CELL_SIZE).floor
  grid_y = (entity.position.y / GRID_CELL_SIZE).floor
  # Check current cell and adjacent cells
  dx = -1
  dy = -1
  c = 0

  while dx <= 1 do 
    while dy <= 1 do 
      check_x = grid_x + dx
      check_y = grid_y + dy
      
      unless check_x < 0 || check_x >= GRID_COLS || check_y < 0 || check_y >= GRID_ROWS
        i = 0
        l = grid[check_x][check_y].length
        while i < l
          blk.call(grid[check_x][check_y][i]) if blk
          i += 1
          c += 1
          return c if c >= MOVEMENT_ACCURACY
        end
      end
      
      dy += 1
    end
    
    dx += 1
    dy = -1
  end

  c
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


def boot(args)
  GTK.dlopen "ext"

  ecs = Drecs.world do 
    debug true
  end

  args.state.ecs = ecs

  ecs.entity do 
    name :grid
    as :grid
    component :data, Array.new(GRID_COLS) { Array.new(GRID_ROWS) { [] } }
  end

  i = 0
  while i < BOIDS_COUNT do 
    ecs.entity do 
      name :boid
      component :position, x: rand * RESOLUTION.w, y: rand * RESOLUTION.h
      component :size, w: Numeric.rand(5..5), h: Numeric.rand(5..5)
      component :color, r: rand(255), g: rand(255), b: rand(255), a: 255

      velocity = Geometry.vec2_normalize({ x: rand - 0.5, y: rand - 0.5 })
      operand = Numeric.rand(MIN_VELOCITY..MAX_VELOCITY)
      velocity = {
        x: velocity.x * operand,
        y: velocity.y * operand
      }
      component :velocity, velocity

      draw do |ffi_draw|
        next unless position && size && color
        ffi_draw.draw_solid(
          position.x, position.y, size.w, size.h,
          color.r, color.g, color.b, color.a
        )
      end
    end

    i += 1
  end

  ecs.query do 
    with(:position)
    as :positions
  end

  ecs.query do 
    with(:position, :velocity)
    as :boids
  end

  ecs.query do 
    with(:position, :size, :color)
    as :renderables
  end
end

def tick(args)
  now = Time.now 
  args.state.delta_time = now - (args.state.last_time || now - 0.016)
  args.state.last_time = now
  
  ecs = args.state.ecs
  ecs.query.raw do |_|
    x = 0
    y = 0
    while x < GRID_COLS
      while y < GRID_ROWS
        ecs.grid.data[x][y].clear
        y += 1
      end
      x += 1
      y = 0
    end
  end

  ecs.positions.each do |entity| 
    grid_x = (entity.position.x / GRID_CELL_SIZE).floor.clamp(0, GRID_COLS - 1)
    grid_y = (entity.position.y / GRID_CELL_SIZE).floor.clamp(0, GRID_ROWS - 1)
  
    ecs.grid.data[grid_x][grid_y] << entity 
  end

  ecs.boids.job do |entity|
    pos = entity.position
    vel = entity.velocity
    
    # Reset vectors
    COHESION.x = 0
    COHESION.y = 0
    SEPARATION.x = 0
    SEPARATION.y = 0
    ALIGNMENT.x = 0
    ALIGNMENT.y = 0


    neighbour_count = neighbours(entity, ecs.boids, ecs.grid.data) do |other|
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
    
    if neighbour_count > 0
    
      if args.inputs.mouse.left
        MOUSE.x = args.inputs.mouse.x
        MOUSE.y = args.inputs.mouse.y
        COHESION.x = MOUSE.x
        COHESION.y = MOUSE.y
      else
        vec2_div(COHESION, neighbour_count)
      end
      vec2_sub(COHESION, pos)
      vec2_div(COHESION, COHESION_DIVISOR)
      vec2_mul(COHESION, COHESION_WEIGHT)
      
      vec2_mul(SEPARATION, SEPARATION_WEIGHT)
      
      vec2_div(ALIGNMENT, neighbour_count)
      vec2_sub(ALIGNMENT, vel)
      vec2_div(ALIGNMENT, ALIGNMENT_DIVISOR)
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
    end

    # Update position
    vec2_add(pos, vel)
    
    if BOUNCE 
      vel.x = -vel.x if pos.x < 0 || pos.x > RESOLUTION[:w]
      vel.y = -vel.y if pos.y < 0 || pos.y > RESOLUTION[:h]
    else 
      pos.x = (pos.x + RESOLUTION[:w]) % RESOLUTION[:w]
      pos.y = (pos.y + RESOLUTION[:h]) % RESOLUTION[:h]
    end
  end

  args.outputs.solids << ecs.renderables.to_a

  if args.inputs.keyboard.key_down.space
    ecs.renderables.to_a.sample.remove(:color)
  end


  args.outputs.debug << "#{args.gtk.current_framerate} fps"
  args.outputs.debug << "#{args.gtk.current_framerate_calc} fps simulation"
  args.outputs.debug << "#{args.gtk.current_framerate_render} fps render"
  args.outputs.debug << "boids: #{BOIDS_COUNT}"

end