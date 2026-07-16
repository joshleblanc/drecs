# Destroyed component - marks entity for removal
class Destroyed
  include Drecs::Component
  component :destroyed_at

  def initialize(frame = 0)
    @destroyed_at = frame
  end
end