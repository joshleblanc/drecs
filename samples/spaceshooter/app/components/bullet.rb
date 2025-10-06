class Bullet < Struct.new(:damage)
  def initialize(damage = 1)
    super(damage)
  end
end
