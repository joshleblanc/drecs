class Lifetime
  include Drecs::Component
  component :ticks

  def initialize(ticks = 120)
    @ticks = ticks
  end
end
