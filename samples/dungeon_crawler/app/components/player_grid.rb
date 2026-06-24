# PlayerGrid component - stores player position in tile coordinates
# Used for grid-based movement where player snaps to tiles
class PlayerGrid < Struct.new(:grid_x, :grid_y, :facing)
  TILE_SIZE = 32

  DIRECTIONS = [:up, :down, :left, :right].freeze

  def initialize(grid_x = 0, grid_y = 0, facing = :down)
    super(grid_x, grid_y, facing)
  end

  # Convert tile coordinates to pixel coordinates (top-left of tile)
  def to_pixel
    { x: grid_x * TILE_SIZE, y: grid_y * TILE_SIZE }
  end

  # Convert to pixel coordinates centered in tile
  def to_pixel_centered
    { x: grid_x * TILE_SIZE + TILE_SIZE / 2, y: grid_y * TILE_SIZE + TILE_SIZE / 2 }
  end

  # Get the target tile coordinates in the facing direction
  # Note: y increases UP in screen coords, so "down" key means y-1 visually
  def target_tile
    case facing
    when :up    then { x: grid_x, y: grid_y + 1 }  # y+1 = visually up
    when :down  then { x: grid_x, y: grid_y - 1 }  # y-1 = visually down
    when :left  then { x: grid_x - 1, y: grid_y }
    when :right then { x: grid_x + 1, y: grid_y }
    else            { x: grid_x, y: grid_y }
    end
  end

  # Get directional offset for movement
  def direction_vector
    case facing
    when :up    then { dx: 0, dy: -1 }
    when :down  then { dx: 0, dy: 1 }
    when :left  then { dx: -1, dy: 0 }
    when :right then { dx: 1, dy: 0 }
    else            { dx: 0, dy: 0 }
    end
  end

  def move!(dx, dy)
    self.grid_x += dx
    self.grid_y += dy
  end

  def move_toward(direction)
    case direction
    when :up    then move!(0, 1)   # y+1 = visually up
    when :down  then move!(0, -1)  # y-1 = visually down
    when :left  then move!(-1, 0)
    when :right then move!(1, 0)
    end
    self.facing = direction
  end

  def turn_left
    self.facing = DIRECTIONS[(DIRECTIONS.index(facing) || 0 + 3) % 4]
  end

  def turn_right
    self.facing = DIRECTIONS[(DIRECTIONS.index(facing) || 0 + 1) % 4]
  end
end