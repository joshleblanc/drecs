# Loot component - tag for dropped items
class Loot < Struct.new(:value)
  def initialize(value = 10)
    super(value)
  end
end