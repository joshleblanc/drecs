class Enemy
  include Drecs::Component
  component :direction

  def initialize(direction = 1)
    @direction = direction
  end
end
