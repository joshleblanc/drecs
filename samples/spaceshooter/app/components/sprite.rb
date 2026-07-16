class Sprite
  include Drecs::Component
  component :w, :h, :r, :g, :b, :a

  def initialize(w, h, r = 255, g = 255, b = 255, a = 255)
    @w = w
    @h = h
    @r = r
    @g = g
    @b = b
    @a = a
  end
end
