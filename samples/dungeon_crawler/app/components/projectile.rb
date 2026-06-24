# Projectile component - tag for bullets/attacks
class Projectile < Struct.new(:damage, :owner_id)
  def initialize(damage = 20, owner_id = nil)
    super(damage, owner_id)
  end
end