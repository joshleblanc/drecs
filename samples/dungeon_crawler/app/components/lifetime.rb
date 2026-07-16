# Lifetime component - for entities that should be destroyed after a time
class Lifetime
  include Drecs::Component
  component :ttl

  def initialize(ttl = 120)
    @ttl = ttl
  end

  def expired?
    ttl <= 0
  end

  def tick!
    self.ttl -= 1
  end
end