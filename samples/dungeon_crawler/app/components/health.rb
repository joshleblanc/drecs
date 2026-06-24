class Health < Struct.new(:current, :max)
  def initialize(current = 100, max = 100)
    super(current, max)
  end

  def dead?
    current <= 0
  end

  def hurt(amount)
    self.current = [0, current - amount].max
  end

  def heal(amount)
    self.current = [max, current + amount].min
  end

  def ratio
    return 0 if max == 0
    current.to_f / max
  end

  def alive?
    current > 0
  end
end