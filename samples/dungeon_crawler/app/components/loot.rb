# Loot component - tag for dropped items
class Loot
  include Drecs::Component
  component :value

  def initialize(value = 10)
    @value = value
  end
end