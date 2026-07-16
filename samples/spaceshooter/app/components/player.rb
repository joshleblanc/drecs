class Player
  include Drecs::Component
  component :speed, :fire_cooldown

  def initialize(speed = 5, fire_cooldown = 0)
    @speed = speed
    @fire_cooldown = fire_cooldown
  end
end
