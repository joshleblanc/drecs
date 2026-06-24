class Sprite < Struct.new(:w, :h, :r, :g, :b, :a)
  def initialize(w, h, r = 255, g = 255, b = 255, a = 255)
    super(w, h, r, g, b, a)
  end

  def color
    { r: r, g: g, b: b, a: a }
  end

  def set_color(new_r, new_g, new_b, new_a = 255)
    Sprite.new(w, h, new_r, new_g, new_b, new_a)
  end
end