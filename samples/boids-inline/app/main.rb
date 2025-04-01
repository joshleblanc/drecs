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
GRID_POS_FACTOR = 1.0 / GRID_CELL_SIZE
GRID_COLS = (RESOLUTION.w / GRID_CELL_SIZE).ceil
GRID_ROWS = (RESOLUTION.h / GRID_CELL_SIZE).ceil
MAX_GRID_COLS = GRID_COLS - 1
MAX_GRID_ROWS = GRID_ROWS - 1

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

  def div!(scalar)
    return self if scalar.zero?
    self.x /= scalar
    self.y /= scalar
    self
  end

  def add!(other)
    self.x += other.x
    self.y += other.y
    self
  end

  def sub!(other)
    self.x -= other.x
    self.y -= other.y
    self
  end

  def magnitude
    Geometry.vec2_magnitude(self)
  end

  def normalize!
    m = magnitude
    return self if m.zero?
    self.x /= m
    self.y /= m
    self
  end
end

COHESION = Vector.new(0, 0)
SEPARATION = Vector.new(0, 0)
ALIGNMENT = Vector.new(0, 0)
DIFF = Vector.new(0, 0)
MOUSE = Vector.new(0, 0)

ALIGNMENT_DIVISOR = 4
COHESION_DIVISOR = 100

def neighbours(entity, grid, &blk)
  grid_x = (entity.position.x * GRID_POS_FACTOR).floor
  grid_y = (entity.position.y * GRID_POS_FACTOR).floor
  c = 0
  dx = -1

  while dx <= 1
    dy = -1
    while dy <= 1
      check_x = grid_x + dx
      check_y = grid_y + dy
      
      if check_x < 0 || check_x >= GRID_COLS || check_y < 0 || check_y >= GRID_ROWS
        dy += 1
        next 
      end

      cell = grid[check_x][check_y]
      i = 0
      l = cell.length
      while i < l
        blk.call(cell[i]) if blk
        i += 1
        c += 1
        return c if c >= MOVEMENT_ACCURACY
      end
      
      dy += 1
    end
    dx += 1
  end

  c
end


def boot(args)
  args.state.entities = Drecs.world

  args.state.entities.entity do 
    name :grid
    as :grid
    component :data, Array.new(GRID_COLS) { Array.new(GRID_ROWS) { [] } }
  end

  i = 0
  while i < BOIDS_COUNT do 
    args.state.entities << { 
      position: Vector.new(rand * RESOLUTION.w, rand * RESOLUTION.h),
      size: Vector.new(5, 5),
      color: { r: rand(255), g: rand(255), b: rand(255), a: 255 },
      velocity: Vector.new(rand - 0.5, rand - 0.5).normalize!.mul!(Numeric.rand(MIN_VELOCITY..MAX_VELOCITY)),
      draw: ->(ffi_draw) do 
        next unless position && size && color
        ffi_draw.draw_solid(
          position.x, position.y, size.x, size.y,
          color.r, color.g, color.b, color.a
        )
      end
    }
    i += 1
  end

  args.state.entities.query do 
    with(:position)
    as :positions
  end

  args.state.entities.query do 
    with(:position, :velocity)
    as :boids
  end

  args.state.entities.query do 
    with(:position, :size, :color)
    as :renderables
  end

  args.state.entities.query do 
    with(:position, :velocity)
    as :boids
  end
end

def tick(args)
  now = Time.now 
  args.state.delta_time = now - (args.state.last_time || now - 0.016)
  args.state.last_time = now

  grid = args.state.entities.grid.data

  grid.replace(Array.new(GRID_COLS) { Array.new(GRID_ROWS) { [] }})

  args.state.entities.positions.each do |entity| 
    grid_x = (entity.position.x.to_i * GRID_POS_FACTOR).clamp(0, MAX_GRID_COLS)
    grid_y = (entity.position.y.to_i * GRID_POS_FACTOR).clamp(0, MAX_GRID_ROWS)
  
    grid[grid_x][grid_y] << entity 
  end

  args.state.entities.boids.each do |entity|
    pos = entity.position
    vel = entity.velocity
    
    # Reset vectors
    COHESION.clear!
    SEPARATION.clear!
    ALIGNMENT.clear!


    neighbour_count = neighbours(entity, grid) do |other|
      other_pos = other.position
      other_vel = other.velocity
      
      # Calculate separation
      DIFF.x = pos.x - other_pos.x
      DIFF.y = pos.y - other_pos.y
      
      dist = DIFF.magnitude
      if dist < NEIGHBOUR_RANGE && dist > 0
        scale = 1.0 / dist
        DIFF.div!(dist)
        DIFF.mul!(scale)
        SEPARATION.add!(DIFF)
      end
      
      # Accumulate cohesion and alignment
      COHESION.add!(other_pos)
      ALIGNMENT.add!(other_vel)
    end
    
    if neighbour_count > 0
    
      if args.inputs.mouse.left
        MOUSE.x = args.inputs.mouse.x
        MOUSE.y = args.inputs.mouse.y
        COHESION.x = MOUSE.x
        COHESION.y = MOUSE.y
      else
        COHESION.div!(neighbour_count)
      end
      COHESION.sub!(pos)
      COHESION.div!(COHESION_DIVISOR)
      COHESION.mul!(COHESION_WEIGHT)
      
      SEPARATION.mul!(SEPARATION_WEIGHT)
      
      ALIGNMENT.div!(neighbour_count)
      ALIGNMENT.sub!(vel)
      ALIGNMENT.div!(ALIGNMENT_DIVISOR)
      ALIGNMENT.mul!(ALIGNMENT_WEIGHT)
      
      # Combine forces and update velocity
      COHESION.add!(SEPARATION)
      COHESION.add!(ALIGNMENT)
      vel.add!(COHESION)
      
      # Constrain velocity in place
      magnitude = vel.magnitude
      if magnitude < MIN_VELOCITY
        scale = MIN_VELOCITY / magnitude
        vel.mul!(scale)
      elsif magnitude > MAX_VELOCITY
        scale = MAX_VELOCITY / magnitude
        vel.mul!(scale)
      end
    end

    # Update position
    pos.add!(vel)
    vel.mul!(args.state.delta_time * 100)
    
    if BOUNCE 
      vel.x = -vel.x if pos.x < 0 || pos.x > RESOLUTION[:w]
      vel.y = -vel.y if pos.y < 0 || pos.y > RESOLUTION[:h]
    else 
      pos.x = (pos.x + RESOLUTION[:w]) % RESOLUTION[:w]
      pos.y = (pos.y + RESOLUTION[:h]) % RESOLUTION[:h]
    end
  end

  args.outputs.solids << args.state.entities.with(:position, :size, :color).to_a

  if args.inputs.keyboard.key_down.space
    args.state.entities.with(:position, :size, :color).to_a.sample.remove(:color)
  end


  args.outputs.debug << "#{args.gtk.current_framerate} fps"
  args.outputs.debug << "#{args.gtk.current_framerate_calc} fps simulation"
  args.outputs.debug << "#{args.gtk.current_framerate_render} fps render"
  args.outputs.debug << "boids: #{BOIDS_COUNT}"

end