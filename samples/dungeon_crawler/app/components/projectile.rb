# Projectile component - tag for bullets/attacks
class Projectile
  include Drecs::Component
  component :damage, :owner_id

  def initialize(damage = 20, owner_id = nil)
    @damage = damage
    @owner_id = owner_id
  end
end