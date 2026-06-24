# Destroyed component - marks entity for removal
class Destroyed < Struct.new(:destroyed_at)
  def initialize(frame = 0)
    super(frame)
  end
end