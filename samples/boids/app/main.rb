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

# Component classes for the new ECS API. Distinct classes are required so they
# can coexist on the same entity archetype.
Position = Class.new(Vector)
Velocity = Class.new(Vector)
Size     = Class.new(Vector)
Color    = Struct.new(:r, :g, :b, :a)
Grid     = Struct.new(:cells)

COHESION = Vector.new(0, 0)
SEPARATION = Vector.new(0, 0)
ALIGNMENT = Vector.new(0, 0)
DIFF = Vector.new(0, 0)
MOUSE = Vector.new(0, 0)

ALIGNMENT_DIVISOR = 4
COHESION_DIVISOR = 100

def neighbours(index, grid, positions, &blk)
  grid_x = (positions[index].x * GRID_POS_FACTOR).floor
  grid_y = (positions[index].y * GRID_POS_FACTOR).floor
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
  args.state.entities = Drecs::World.new

  # Create a single grid component entity to hold spatial buckets
  args.state.grid = Grid.new(Array.new(GRID_COLS) { Array.new(GRID_ROWS) { [] } })
  args.state.entities.spawn(args.state.grid)

  i = 0
  while i < BOIDS_COUNT
    pos = Position.new(rand * RESOLUTION.w, rand * RESOLUTION.h)
    size = Size.new(5, 5)
    color = Color.new(rand(255), rand(255), rand(255), 255)

    # Random normalized direction with speed between min and max
    vel = Velocity.new(rand - 0.5, rand - 0.5).normalize!
    speed = MIN_VELOCITY + rand * (MAX_VELOCITY - MIN_VELOCITY)
    vel.mul!(speed)

    args.state.entities.spawn(pos, size, color, vel)
    i += 1
  end
end

def tick(args)
  now = Time.now 
  args.state.delta_time = now - (args.state.last_time || now - 0.016)
  args.state.last_time = now

  grid = args.state.grid.cells
  grid.replace(Array.new(GRID_COLS) { Array.new(GRID_ROWS) { [] } })

  solids = []

  # Work on boids using the new ECS query API. The arrays are aligned by index.
  args.state.entities.query(Position, Velocity, Size, Color) do |positions, velocities, sizes, colors|
    # Populate spatial grid with boid indices
    positions.each_with_index do |pos, i|
      grid_x = (pos.x.to_i * GRID_POS_FACTOR).clamp(0, MAX_GRID_COLS)
      grid_y = (pos.y.to_i * GRID_POS_FACTOR).clamp(0, MAX_GRID_ROWS)
      grid[grid_x][grid_y] << i
    end

    # Simulation update
    positions.each_with_index do |pos, i|
      vel = velocities[i]

      # Reset steering accumulators
      COHESION.clear!
      SEPARATION.clear!
      ALIGNMENT.clear!

      neighbour_count = neighbours(i, grid, positions) do |j|
        other_pos = positions[j]
        other_vel = velocities[j]

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

      # Integrate position and apply bounds/wrap
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

    # Build solids for rendering
    positions.each_with_index do |pos, i|
      size = sizes[i]
      color = colors[i]
      solids << {
        x: pos.x,
        y: pos.y,
        w: size.x,
        h: size.y,
        r: color.r,
        g: color.g,
        b: color.b,
        a: color.a
      }
    end
  end

  args.outputs.solids << solids

  args.outputs.debug << "#{args.gtk.current_framerate} fps"
  args.outputs.debug << "#{args.gtk.current_framerate_calc} fps simulation"
  args.outputs.debug << "#{args.gtk.current_framerate_render} fps render"
  args.outputs.debug << "boids: #{BOIDS_COUNT}"
end