class Velocity < Struct.new(:dx, :dy)
  def initialize(dx = 0, dy = 0)
    super(dx, dy)
  end

  def moving?
    dx != 0 || dy != 0
  end

  def speed
    Math.sqrt(dx * dx + dy * dy)
  end

  def opposite
    Velocity.new(-dx, -dy)
  end
end