# Item component - represents collectible items
# type: :health, :key, :gold, :weapon
class Item
  include Drecs::Component
  component :type, :value

  def initialize(type = :gold, value = 10)
    @type = type
    @value = value
  end
end