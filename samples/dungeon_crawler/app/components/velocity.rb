class Velocity
  include Drecs::Component
  component :dx, :dy

  def initialize(dx = 0, dy = 0)
    @dx = dx
    @dy = dy
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