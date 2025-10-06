class Velocity < Struct.new(:x, :y)
  def initialize(x = 0, y = 0)
    super(x, y)
  end
end
