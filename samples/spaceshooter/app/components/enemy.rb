class Enemy < Struct.new(:direction)
  def initialize(direction = 1)
    super(direction)
  end
end
