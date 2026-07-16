class Velocity
  include Drecs::Component
  component :x, :y

  def initialize(x = 0, y = 0)
    @x = x
    @y = y
  end
end
