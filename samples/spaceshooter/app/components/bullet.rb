class Bullet
  include Drecs::Component
  component :damage

  def initialize(damage = 1)
    @damage = damage
  end
end
