class Collider
  include Drecs::Component
  component :radius

  def initialize(radius = 16)
    @radius = radius
  end

  def diameter
    radius * 2
  end

  def collides_with?(other_pos, other_radius)
    dx = other_pos.x - 0 # caller passes entity position
    dy = other_pos.y - 0
    distance = Math.sqrt(dx * dx + dy * dy)
    distance < radius + other_radius.radius
  end
end