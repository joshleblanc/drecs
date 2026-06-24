# Item component - represents collectible items
# type: :health, :key, :gold, :weapon
class Item < Struct.new(:type, :value)
  def initialize(type = :gold, value = 10)
    super(type, value)
  end
end