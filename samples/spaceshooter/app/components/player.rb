class Player < Struct.new(:speed, :fire_cooldown)
  def initialize(speed = 5, fire_cooldown = 0)
    super(speed, fire_cooldown)
  end
end
