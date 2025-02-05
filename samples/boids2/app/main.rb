
RESOLUTION = {
  w: 1280,
  h: 720
}

BOIDS_COUNT = 2000

SEPARATION_WEIGHT = 20
ALIGNMENT_WEIGHT = 1.0
COHESION_WEIGHT = 1.0

MOVEMENT_ACCURACY = 1

NEIGHBOUR_RANGE = 20
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
        while i < grid[check_x][check_y].size
          blk.call(grid[check_x][check_y][i]) if blk
          i += 1
          c += 1
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
  ecs = Drecs.world do 
    debug false
  end

  ecs.entity do 
    name :grid
    as :grid
    component :data, Array.new(GRID_COLS) { Array.new(GRID_ROWS) { [] } }
  end

  ecs.system do
    name :setup
    callback do
      BOIDS_COUNT.times do 
        world.entity do 
          name :boid
          component :position, x: rand * RESOLUTION.w, y: rand * RESOLUTION.h
          component :size, w: Numeric.rand(5..5), h: Numeric.rand(5..5)
          component :color, r: rand(255), g: rand(255), b: rand(255), a: 255

          velocity = Geometry.vec2_normalize({ x: rand - 0.5, y: rand - 0.5 })
          operand = (MIN_VELOCITY + (rand * (MAX_VELOCITY - MIN_VELOCITY)))
          velocity = {
            x: velocity.x * operand,
            y: velocity.y * operand
          }
          component :velocity, velocity

          def draw_override(ffi_draw)
            ffi_draw.draw_solid(
              position.x, position.y, size.w, size.h,
              color.r, color.g, color.b, color.a
            )
          end
        end
      end

      disable!
    end
  end

  ecs.system do
    name :clear_grid 
    callback do 
      x = 0
      y = 0
      while x < GRID_COLS
        while y < GRID_ROWS
          world.grid.data[x][y].clear
          y += 1
        end
        x += 1
        y = 0
      end
    end
  end
  
  ecs.system do 
    name :update_grid
    query { with(:position) }
    callback do |entity| 
      # Clear the grid
      grid_x = (entity.position.x / GRID_CELL_SIZE).floor.clamp(0, GRID_COLS - 1)
      grid_y = (entity.position.y / GRID_CELL_SIZE).floor.clamp(0, GRID_ROWS - 1)

      world.grid.data[grid_x][grid_y].clear
      world.grid.data[grid_x][grid_y] << entity 
    end
  end

  ecs.system do 
    name :movement
    query { with(:position, :velocity) }
    callback do |entity|
      pos = entity.position
      vel = entity.velocity
      
      # Reset vectors
      COHESION.x = 0
      COHESION.y = 0
      SEPARATION.x = 0
      SEPARATION.y = 0
      ALIGNMENT.x = 0
      ALIGNMENT.y = 0

  
      neighbour_count = neighbours(entity, world.query { with(:position, :velocity) }, world.grid.data) do |other|
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
      
      next if neighbour_count == 0
      
      if args.inputs.mouse.left
        MOUSE.x = args.inputs.mouse.x
        MOUSE.y = args.inputs.mouse.y
        COHESION.x = MOUSE.x
        COHESION.y = MOUSE.y
      else
        vec2_div(COHESION, neighbour_count)
      end
      vec2_sub(COHESION, pos)
      vec2_div(COHESION, 100)
      vec2_mul(COHESION, COHESION_WEIGHT)
      
      vec2_mul(SEPARATION, SEPARATION_WEIGHT)
      
      vec2_div(ALIGNMENT, neighbour_count)
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
    end
  end

  ecs.system do 
    name :draw 
    callback do 
      args.outputs.solids << world.query { with(:position, :size, :color) }
    end
  end

  $args.state.worlds[:default] = ecs
end

def tick(args)
  $args.state.worlds[:default].tick(args)
  args.outputs.debug << "#{args.gtk.current_framerate} fps"
  args.outputs.debug << "#{args.gtk.current_framerate_calc} fps simulation"
  args.outputs.debug << "#{args.gtk.current_framerate_render} fps render"
  args.outputs.debug << "boids: #{BOIDS_COUNT}"
end