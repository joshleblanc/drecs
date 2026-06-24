class Position < Struct.new(:x, :y)
  def initialize(x = 0, y = 0)
    super(x, y)
  end

  def to_pixel_offset(tile_size = 32)
    { x: x * tile_size, y: y * tile_size }
  end

  def manhattan_distance(other)
    (x - other.x).abs + (y - other.y).abs
  end

  def adjacent?(other)
    manhattan_distance(other) == 1
  end
end