class Lifetime < Struct.new(:ticks)
  def initialize(ticks = 120)
    super(ticks)
  end
end
