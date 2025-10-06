class Sprite < Struct.new(:w, :h, :r, :g, :b, :a)
  def initialize(w, h, r = 255, g = 255, b = 255, a = 255)
    super(w, h, r, g, b, a)
  end
end
